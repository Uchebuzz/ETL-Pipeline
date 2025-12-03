#!/bin/bash
# Script to import existing AWS resources into Terraform state
# This prevents "already exists" errors when applying Terraform

# Don't use set -e - we want to continue processing even if some imports fail
# We'll track failures and exit with error at the end if critical imports failed
IMPORT_FAILURES=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure we're in the terraform directory or find it
if [ -f "terraform.tf" ] || [ -f "main.tf" ]; then
    TERRAFORM_DIR="."
elif [ -d "terraform" ] && [ -f "terraform/main.tf" ]; then
    TERRAFORM_DIR="terraform"
else
    echo -e "${RED}Error: Could not find Terraform directory${NC}"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Verify terraform is initialized
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Warning: Terraform not initialized. Running terraform init...${NC}"
    terraform init -input=false >/dev/null 2>&1 || {
        echo -e "${RED}Error: Failed to initialize Terraform${NC}"
        exit 1
    }
fi

# Ensure lambda_package directory exists to avoid data source errors during import
# This is needed because data.archive_file.lambda_zip depends on this directory
PROJECT_ROOT="$(cd .. && pwd)"
LAMBDA_PACKAGE_DIR="$PROJECT_ROOT/lambda_package"
if [ ! -d "$LAMBDA_PACKAGE_DIR" ]; then
    echo -e "${YELLOW}Creating lambda_package directory to avoid data source errors...${NC}"
    mkdir -p "$LAMBDA_PACKAGE_DIR"
    # Create a minimal placeholder if lambda_handler.py exists
    if [ -f "$PROJECT_ROOT/lambda_handler.py" ]; then
        cp "$PROJECT_ROOT/lambda_handler.py" "$LAMBDA_PACKAGE_DIR/" 2>/dev/null || true
    else
        # Create a minimal placeholder file
        echo "# Placeholder for lambda package" > "$LAMBDA_PACKAGE_DIR/.placeholder"
    fi
fi

echo -e "${GREEN}Starting resource import process...${NC}"

# Get variables from environment or use defaults
PROJECT_NAME="${TF_VAR_project_name:-etl-pipeline}"
ENV="${TF_VAR_environment:-dev}"
AWS_REGION="${TF_VAR_aws_region:-us-east-1}"
SOURCE_BUCKET="${TF_VAR_source_bucket_name}"
DEST_BUCKET="${TF_VAR_destination_bucket_name}"
GLUE_SCRIPTS_BUCKET="${TF_VAR_glue_scripts_bucket_name:-${PROJECT_NAME}-glue-scripts-${ENV}}"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not get AWS account ID. Check your AWS credentials.${NC}"
    exit 1
fi

echo "Project: $PROJECT_NAME"
echo "Environment: $ENV"
echo "Region: $AWS_REGION"
echo "AWS Account: $AWS_ACCOUNT_ID"
echo ""

# Function to try importing a resource
import_resource() {
    local resource_address=$1
    local resource_id=$2
    local description=$3
    local project_root="$(cd .. && pwd)"
    local lambda_package_dir="$project_root/lambda_package"
    
    echo -n "Importing $description... "
    
    # Check if resource is already in state
    if terraform state show "$resource_address" >/dev/null 2>&1; then
        echo -e "${YELLOW}Already in state${NC}"
        return 0
    fi
    
    # Try to import (terraform import doesn't support -refresh flag)
    # Use -input=false to avoid prompts and -lock=false to avoid locking issues
    IMPORT_OUTPUT=$(terraform import -input=false -lock=false "$resource_address" "$resource_id" 2>&1)
    IMPORT_EXIT_CODE=$?
    
    if [ $IMPORT_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}Success${NC}"
        return 0
    else
        # Check if error is because resource doesn't exist or is already managed
        if echo "$IMPORT_OUTPUT" | grep -qiE "already managed by Terraform|does not exist|ResourceNotFoundException"; then
            echo -e "${YELLOW}Not found or already managed${NC}"
            # Return 0 for expected "not found" cases - this is normal for new deployments
            return 0
        else
            # Check if it's a data source error - try to work around it
            if echo "$IMPORT_OUTPUT" | grep -qiE "data\.[^:]*: Reading|Error reading|Failed to read|No such file or directory"; then
                echo -e "${YELLOW}Data source dependency issue detected${NC}"
                echo -e "${YELLOW}  Attempting to create missing dependencies...${NC}"
                
                # Try to ensure lambda package is ready
                if [ -d "$lambda_package_dir" ] && [ ! -f "$project_root/terraform/lambda_function.zip" ]; then
                    # Create a minimal zip file if it doesn't exist and zip command is available
                    if command -v zip >/dev/null 2>&1; then
                        cd "$lambda_package_dir"
                        zip -q "$project_root/terraform/lambda_function.zip" ./* 2>/dev/null || true
                        cd "$TERRAFORM_DIR"
                    fi
                fi
                
                # Try import again
                IMPORT_OUTPUT2=$(terraform import -input=false -lock=false "$resource_address" "$resource_id" 2>&1)
                IMPORT_EXIT_CODE2=$?
                
                if [ $IMPORT_EXIT_CODE2 -eq 0 ]; then
                    echo -e "${GREEN}Success (after fixing dependencies)${NC}"
                    return 0
                else
                    echo -e "${YELLOW}Warning: Still failing due to data source dependency${NC}"
                    echo -e "${YELLOW}  Error: $(echo "$IMPORT_OUTPUT2" | head -n 1)${NC}"
                    echo -e "${YELLOW}  You may need to run 'terraform apply' once to create dependencies, then import${NC}"
                    return 1
                fi
            else
                echo -e "${RED}Failed: $(echo "$IMPORT_OUTPUT" | head -n 1)${NC}"
                # Return 1 for unexpected errors - these need to be fixed
                return 1
            fi
        fi
    fi
}

# Import S3 Buckets
if [ -n "$SOURCE_BUCKET" ]; then
    import_resource "aws_s3_bucket.source" "$SOURCE_BUCKET" "Source S3 bucket ($SOURCE_BUCKET)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
fi

if [ -n "$DEST_BUCKET" ]; then
    import_resource "aws_s3_bucket.destination" "$DEST_BUCKET" "Destination S3 bucket ($DEST_BUCKET)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
fi

import_resource "aws_s3_bucket.glue_scripts" "$GLUE_SCRIPTS_BUCKET" "Glue scripts S3 bucket ($GLUE_SCRIPTS_BUCKET)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))

# Import CloudWatch Log Group (only if enable_cloudwatch is true)
if [ "${TF_VAR_enable_cloudwatch:-true}" = "true" ]; then
    LOG_GROUP_NAME="${PROJECT_NAME}-${ENV}"
    import_resource "aws_cloudwatch_log_group.etl_pipeline[0]" "$LOG_GROUP_NAME" "CloudWatch Log Group ($LOG_GROUP_NAME)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
fi

# Import IAM Roles
LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role-${ENV}"
GLUE_ROLE_NAME="${PROJECT_NAME}-glue-role-${ENV}"

import_resource "aws_iam_role.lambda_role" "$LAMBDA_ROLE_NAME" "Lambda IAM Role ($LAMBDA_ROLE_NAME)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
import_resource "aws_iam_role.glue_role" "$GLUE_ROLE_NAME" "Glue IAM Role ($GLUE_ROLE_NAME)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))

# Import Lambda Function
LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-etl-${ENV}"
import_resource "aws_lambda_function.etl_pipeline" "$LAMBDA_FUNCTION_NAME" "Lambda Function ($LAMBDA_FUNCTION_NAME)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))

# Import Glue Job
GLUE_JOB_NAME="${PROJECT_NAME}-etl-job-${ENV}"
import_resource "aws_glue_job.etl_job" "$GLUE_JOB_NAME" "Glue Job ($GLUE_JOB_NAME)" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))

# Import IAM Role Policies (these are trickier - they use role name + policy name)
if terraform state show aws_iam_role.lambda_role >/dev/null 2>&1; then
    LAMBDA_CLOUDWATCH_POLICY_NAME="${PROJECT_NAME}-lambda-cloudwatch-policy-${ENV}"
    LAMBDA_GLUE_POLICY_NAME="${PROJECT_NAME}-lambda-glue-policy-${ENV}"
    
    import_resource "aws_iam_role_policy.lambda_cloudwatch_policy" "${LAMBDA_ROLE_NAME}:${LAMBDA_CLOUDWATCH_POLICY_NAME}" "Lambda CloudWatch Policy" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
    import_resource "aws_iam_role_policy.lambda_glue_policy" "${LAMBDA_ROLE_NAME}:${LAMBDA_GLUE_POLICY_NAME}" "Lambda Glue Policy" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
fi

if terraform state show aws_iam_role.glue_role >/dev/null 2>&1; then
    GLUE_S3_POLICY_NAME="${PROJECT_NAME}-glue-s3-policy-${ENV}"
    GLUE_CLOUDWATCH_POLICY_NAME="${PROJECT_NAME}-glue-cloudwatch-policy-${ENV}"
    
    import_resource "aws_iam_role_policy.glue_s3_policy" "${GLUE_ROLE_NAME}:${GLUE_S3_POLICY_NAME}" "Glue S3 Policy" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
    import_resource "aws_iam_role_policy.glue_cloudwatch_policy" "${GLUE_ROLE_NAME}:${GLUE_CLOUDWATCH_POLICY_NAME}" "Glue CloudWatch Policy" || IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
fi

# Import S3 Bucket Configurations (these depend on buckets being imported first)
# These are less critical, so we'll continue even if they fail
if terraform state show aws_s3_bucket.source >/dev/null 2>&1 && [ -n "$SOURCE_BUCKET" ]; then
    import_resource "aws_s3_bucket_versioning.source" "$SOURCE_BUCKET" "Source bucket versioning" || true
    import_resource "aws_s3_bucket_server_side_encryption_configuration.source" "$SOURCE_BUCKET" "Source bucket encryption" || true
    import_resource "aws_s3_bucket_public_access_block.source" "$SOURCE_BUCKET" "Source bucket public access block" || true
fi

if terraform state show aws_s3_bucket.destination >/dev/null 2>&1 && [ -n "$DEST_BUCKET" ]; then
    import_resource "aws_s3_bucket_versioning.destination" "$DEST_BUCKET" "Destination bucket versioning" || true
    import_resource "aws_s3_bucket_server_side_encryption_configuration.destination" "$DEST_BUCKET" "Destination bucket encryption" || true
    import_resource "aws_s3_bucket_public_access_block.destination" "$DEST_BUCKET" "Destination bucket public access block" || true
fi

if terraform state show aws_s3_bucket.glue_scripts >/dev/null 2>&1; then
    import_resource "aws_s3_bucket_versioning.glue_scripts" "$GLUE_SCRIPTS_BUCKET" "Glue scripts bucket versioning" || true
    import_resource "aws_s3_bucket_server_side_encryption_configuration.glue_scripts" "$GLUE_SCRIPTS_BUCKET" "Glue scripts bucket encryption" || true
    import_resource "aws_s3_bucket_public_access_block.glue_scripts" "$GLUE_SCRIPTS_BUCKET" "Glue scripts bucket public access block" || true
fi

# Import CloudWatch Metric Alarm
if [ "${TF_VAR_enable_cloudwatch:-true}" = "true" ]; then
    ALARM_NAME="${PROJECT_NAME}-errors-${ENV}"
    import_resource "aws_cloudwatch_metric_alarm.etl_pipeline_errors[0]" "$ALARM_NAME" "CloudWatch Metric Alarm ($ALARM_NAME)" || true
fi

echo ""
if [ $IMPORT_FAILURES -gt 0 ]; then
    echo -e "${RED}Import process completed with $IMPORT_FAILURES failure(s)!${NC}"
    echo -e "${YELLOW}Warning: Some resources could not be imported.${NC}"
    echo -e "${YELLOW}If these resources exist in AWS, Terraform will fail to create them.${NC}"
    echo -e "${YELLOW}Please fix the issues (e.g., ensure lambda_package directory exists) and run the import script again.${NC}"
    echo ""
    echo "Run 'terraform plan' to see what Terraform will try to create."
    exit 1
else
    echo -e "${GREEN}Import process completed successfully!${NC}"
    echo "Run 'terraform plan' to verify the state."
    echo ""
    echo "Note: Some resources may show as needing updates after import."
    echo "This is normal - Terraform will reconcile the differences on next apply."
    exit 0
fi

