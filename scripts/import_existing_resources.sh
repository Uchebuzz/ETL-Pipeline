#!/bin/bash
# Script to import existing AWS resources into Terraform state
# This prevents "already exists" errors when applying Terraform

set -e

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
    
    echo -n "Importing $description... "
    
    # Check if resource is already in state
    if terraform state show "$resource_address" >/dev/null 2>&1; then
        echo -e "${YELLOW}Already in state${NC}"
        return 0
    fi
    
    # Try to import
    IMPORT_OUTPUT=$(terraform import "$resource_address" "$resource_id" 2>&1)
    IMPORT_EXIT_CODE=$?
    
    if [ $IMPORT_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}Success${NC}"
        return 0
    else
        # Check if error is because resource doesn't exist or is already managed
        if echo "$IMPORT_OUTPUT" | grep -q "already managed by Terraform\|does not exist\|ResourceNotFoundException"; then
            echo -e "${YELLOW}Not found or already managed${NC}"
            # Return 0 for expected "not found" cases - this is normal for new deployments
            return 0
        else
            echo -e "${YELLOW}Failed: $(echo "$IMPORT_OUTPUT" | head -n 1)${NC}"
            # Return 1 only for unexpected errors
            return 1
        fi
    fi
}

# Import S3 Buckets
# Use || true to prevent script exit on expected "not found" errors
if [ -n "$SOURCE_BUCKET" ]; then
    import_resource "aws_s3_bucket.source" "$SOURCE_BUCKET" "Source S3 bucket ($SOURCE_BUCKET)" || true
fi

if [ -n "$DEST_BUCKET" ]; then
    import_resource "aws_s3_bucket.destination" "$DEST_BUCKET" "Destination S3 bucket ($DEST_BUCKET)" || true
fi

import_resource "aws_s3_bucket.glue_scripts" "$GLUE_SCRIPTS_BUCKET" "Glue scripts S3 bucket ($GLUE_SCRIPTS_BUCKET)" || true

# Import CloudWatch Log Group (only if enable_cloudwatch is true)
if [ "${TF_VAR_enable_cloudwatch:-true}" = "true" ]; then
    LOG_GROUP_NAME="${PROJECT_NAME}-${ENV}"
    import_resource "aws_cloudwatch_log_group.etl_pipeline[0]" "$LOG_GROUP_NAME" "CloudWatch Log Group ($LOG_GROUP_NAME)" || true
fi

# Import IAM Roles
LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role-${ENV}"
GLUE_ROLE_NAME="${PROJECT_NAME}-glue-role-${ENV}"

import_resource "aws_iam_role.lambda_role" "$LAMBDA_ROLE_NAME" "Lambda IAM Role ($LAMBDA_ROLE_NAME)" || true
import_resource "aws_iam_role.glue_role" "$GLUE_ROLE_NAME" "Glue IAM Role ($GLUE_ROLE_NAME)" || true

# Import Lambda Function
LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-etl-${ENV}"
import_resource "aws_lambda_function.etl_pipeline" "$LAMBDA_FUNCTION_NAME" "Lambda Function ($LAMBDA_FUNCTION_NAME)" || true

# Import Glue Job
GLUE_JOB_NAME="${PROJECT_NAME}-etl-job-${ENV}"
import_resource "aws_glue_job.etl_job" "$GLUE_JOB_NAME" "Glue Job ($GLUE_JOB_NAME)" || true

# Import IAM Role Policies (these are trickier - they use role name + policy name)
if terraform state show aws_iam_role.lambda_role >/dev/null 2>&1; then
    LAMBDA_CLOUDWATCH_POLICY_NAME="${PROJECT_NAME}-lambda-cloudwatch-policy-${ENV}"
    LAMBDA_GLUE_POLICY_NAME="${PROJECT_NAME}-lambda-glue-policy-${ENV}"
    
    import_resource "aws_iam_role_policy.lambda_cloudwatch_policy" "${LAMBDA_ROLE_NAME}:${LAMBDA_CLOUDWATCH_POLICY_NAME}" "Lambda CloudWatch Policy" || true
    import_resource "aws_iam_role_policy.lambda_glue_policy" "${LAMBDA_ROLE_NAME}:${LAMBDA_GLUE_POLICY_NAME}" "Lambda Glue Policy" || true
fi

if terraform state show aws_iam_role.glue_role >/dev/null 2>&1; then
    GLUE_S3_POLICY_NAME="${PROJECT_NAME}-glue-s3-policy-${ENV}"
    GLUE_CLOUDWATCH_POLICY_NAME="${PROJECT_NAME}-glue-cloudwatch-policy-${ENV}"
    
    import_resource "aws_iam_role_policy.glue_s3_policy" "${GLUE_ROLE_NAME}:${GLUE_S3_POLICY_NAME}" "Glue S3 Policy" || true
    import_resource "aws_iam_role_policy.glue_cloudwatch_policy" "${GLUE_ROLE_NAME}:${GLUE_CLOUDWATCH_POLICY_NAME}" "Glue CloudWatch Policy" || true
fi

# Import S3 Bucket Configurations (these depend on buckets being imported first)
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
echo -e "${GREEN}Import process completed!${NC}"
echo "Run 'terraform plan' to verify the state."
echo ""
echo "Note: Some resources may show as needing updates after import."
echo "This is normal - Terraform will reconcile the differences on next apply."

