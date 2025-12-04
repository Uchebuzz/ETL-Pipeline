#!/bin/bash
# Script to import existing AWS resources into Terraform state

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# === Load .env file (optional) ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find .env file (check current directory and parent)
ENV_FILE=""
if [ -f "$SCRIPT_DIR/../.env" ]; then
    ENV_FILE="$SCRIPT_DIR/../.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    ENV_FILE="$SCRIPT_DIR/.env"
elif [ -f ".env" ]; then
    ENV_FILE=".env"
fi

# Load from .env file if it exists, otherwise use environment variables already set
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    echo -e "${CYAN}Loading environment variables from $ENV_FILE...${NC}"
    
    # Load and export variables
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Skip lines without '=' separator
        [[ "$line" != *"="* ]] && continue
        
        # Split on '=' (only first occurrence)
        key="${line%%=*}"
        value="${line#*=}"
        
        # Remove leading/trailing whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Skip if key is empty after trimming
        [[ -z "$key" ]] && continue
        
        # Remove quotes if present
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        
        # Map .env variables to Terraform variables and export them (only if not already set)
        case "$key" in
            SOURCE_BUCKET)
                [ -z "${TF_VAR_source_bucket_name:-}" ] && export TF_VAR_source_bucket_name="$value"
                echo -e "  ${NC}Loaded: SOURCE_BUCKET -> TF_VAR_source_bucket_name${NC}"
                ;;
            DESTINATION_BUCKET)
                [ -z "${TF_VAR_destination_bucket_name:-}" ] && export TF_VAR_destination_bucket_name="$value"
                echo -e "  ${NC}Loaded: DESTINATION_BUCKET -> TF_VAR_destination_bucket_name${NC}"
                ;;
            GLUE_SCRIPTS_BUCKET_NAME)
                [ -z "${TF_VAR_glue_scripts_bucket_name:-}" ] && export TF_VAR_glue_scripts_bucket_name="$value"
                echo -e "  ${NC}Loaded: GLUE_SCRIPTS_BUCKET_NAME -> TF_VAR_glue_scripts_bucket_name${NC}"
                ;;
            AWS_REGION)
                [ -z "${TF_VAR_aws_region:-}" ] && export TF_VAR_aws_region="$value"
                echo -e "  ${NC}Loaded: AWS_REGION -> TF_VAR_aws_region${NC}"
                ;;
            ENVIRONMENT)
                [ -z "${TF_VAR_environment:-}" ] && export TF_VAR_environment="$value"
                echo -e "  ${NC}Loaded: ENVIRONMENT -> TF_VAR_environment${NC}"
                ;;
            PROJECT_NAME)
                [ -z "${TF_VAR_project_name:-}" ] && export TF_VAR_project_name="$value"
                echo -e "  ${NC}Loaded: PROJECT_NAME -> TF_VAR_project_name${NC}"
                ;;
            CLOUDWATCH_ENABLED)
                [ -z "${TF_VAR_enable_cloudwatch:-}" ] && export TF_VAR_enable_cloudwatch="$value"
                echo -e "  ${NC}Loaded: CLOUDWATCH_ENABLED -> TF_VAR_enable_cloudwatch${NC}"
                ;;
            AWS_ACCESS_KEY_ID)
                [ -z "${AWS_ACCESS_KEY_ID:-}" ] && export AWS_ACCESS_KEY_ID="$value"
                echo -e "  ${NC}Loaded: AWS_ACCESS_KEY_ID${NC}"
                ;;
            AWS_SECRET_ACCESS_KEY)
                [ -z "${AWS_SECRET_ACCESS_KEY:-}" ] && export AWS_SECRET_ACCESS_KEY="$value"
                echo -e "  ${NC}Loaded: AWS_SECRET_ACCESS_KEY (hidden)${NC}"
                ;;
            AWS_SESSION_TOKEN)
                [ -z "${AWS_SESSION_TOKEN:-}" ] && export AWS_SESSION_TOKEN="$value"
                echo -e "  ${NC}Loaded: AWS_SESSION_TOKEN${NC}"
                ;;
        esac
    done < "$ENV_FILE"
    
    echo -e "${GREEN}Environment variables loaded from .env file.${NC}"
else
    echo -e "${YELLOW}No .env file found. Using environment variables already set (e.g., from CI/CD).${NC}"
fi
# === End .env loading ===

# Find terraform directory
if [ -f "terraform.tf" ] || [ -f "main.tf" ]; then
    TERRAFORM_DIR="."
elif [ -d "terraform" ] && [ -f "terraform/main.tf" ]; then
    TERRAFORM_DIR="terraform"
else
    echo -e "${RED}Error: Could not find Terraform directory${NC}"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Ensure lambda_package directory exists (needed for data.archive_file.lambda_zip)
ROOT_DIR="$(cd .. && pwd)"
LAMBDA_PACKAGE_DIR="$ROOT_DIR/lambda_package"
if [ ! -d "$LAMBDA_PACKAGE_DIR" ]; then
    echo -e "${CYAN}Creating lambda_package directory...${NC}"
    mkdir -p "$LAMBDA_PACKAGE_DIR"
    if [ -f "$ROOT_DIR/lambda_handler.py" ]; then
        cp "$ROOT_DIR/lambda_handler.py" "$LAMBDA_PACKAGE_DIR/"
        echo -e "${GREEN}Copied lambda_handler.py to lambda_package/${NC}"
    else
        echo "# Placeholder" > "$LAMBDA_PACKAGE_DIR/.placeholder"
        echo -e "${YELLOW}Created placeholder file (lambda_handler.py not found)${NC}"
    fi
fi

# Get variables from environment
PROJECT_NAME="${TF_VAR_project_name:-}"
ENV="${TF_VAR_environment:-}"
SOURCE_BUCKET="${TF_VAR_source_bucket_name:-}"
DEST_BUCKET="${TF_VAR_destination_bucket_name:-}"
GLUE_SCRIPTS_BUCKET="${TF_VAR_glue_scripts_bucket_name:-}"
ENABLE_CLOUDWATCH="${TF_VAR_enable_cloudwatch:-true}"

# Validate required variables
if [ -z "$PROJECT_NAME" ] || [ -z "$ENV" ]; then
    echo -e "${RED}Error: Required environment variables not set${NC}"
    echo "Please ensure the following are set in your .env file:"
    echo "  - PROJECT_NAME (currently: ${PROJECT_NAME:-NOT SET})"
    echo "  - ENVIRONMENT (currently: ${ENV:-NOT SET})"
    exit 1
fi

if [ -z "$GLUE_SCRIPTS_BUCKET" ]; then
    echo -e "${RED}Error: GLUE_SCRIPTS_BUCKET_NAME is required${NC}"
    exit 1
fi

# Construct resource names
LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role-${ENV}"
GLUE_ROLE_NAME="${PROJECT_NAME}-glue-role-${ENV}"
LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-etl-${ENV}"
GLUE_JOB_NAME="${PROJECT_NAME}-etl-job-${ENV}"
LOG_GROUP_NAME="${PROJECT_NAME}-${ENV}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Importing AWS Resources into Terraform${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Project: ${PROJECT_NAME}${NC}"
echo -e "${CYAN}Environment: ${ENV}${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Function to check if resource is already in state
resource_in_state() {
    terraform state show "$1" &>/dev/null
    return $?
}

# Function to import resource with checking
import_resource() {
    local tf_address="$1"
    local aws_id="$2"
    local description="$3"
    
    echo -e "${CYAN}Checking $description...${NC}"
    
    if resource_in_state "$tf_address"; then
        echo -e "${YELLOW}  ⚠ Already in state, skipping${NC}"
        return 0
    fi
    
    echo -e "${CYAN}  → Importing...${NC}"
    if terraform import "$tf_address" "$aws_id" 2>&1 | grep -q "Import successful"; then
        echo -e "${GREEN}  ✓ Successfully imported${NC}"
        return 0
    else
        echo -e "${RED}  ✗ Failed to import${NC}"
        return 1
    fi
}

# Initialize terraform if needed
if [ ! -d ".terraform" ]; then
    echo -e "${CYAN}Initializing Terraform...${NC}"
    terraform init
    echo ""
fi

# Import IAM roles
echo -e "${CYAN}=== Importing IAM Roles ===${NC}"
import_resource "aws_iam_role.lambda_role" "$LAMBDA_ROLE_NAME" "Lambda IAM role"
import_resource "aws_iam_role.glue_role" "$GLUE_ROLE_NAME" "Glue IAM role"

# Import S3 buckets
echo ""
echo -e "${CYAN}=== Importing S3 Buckets ===${NC}"
if [ -n "$SOURCE_BUCKET" ]; then
    import_resource "aws_s3_bucket.source" "$SOURCE_BUCKET" "Source S3 bucket"
else
    echo -e "${YELLOW}Skipping source bucket (SOURCE_BUCKET not set in .env)${NC}"
fi

if [ -n "$DEST_BUCKET" ]; then
    import_resource "aws_s3_bucket.destination" "$DEST_BUCKET" "Destination S3 bucket"
else
    echo -e "${YELLOW}Skipping destination bucket (DESTINATION_BUCKET not set in .env)${NC}"
fi

import_resource "aws_s3_bucket.glue_scripts" "$GLUE_SCRIPTS_BUCKET" "Glue scripts S3 bucket"

# Import Glue job
echo ""
echo -e "${CYAN}=== Importing Glue Job ===${NC}"
import_resource "aws_glue_job.etl_job" "$GLUE_JOB_NAME" "Glue ETL job"

# Import Lambda function
echo ""
echo -e "${CYAN}=== Importing Lambda Function ===${NC}"
import_resource "aws_lambda_function.etl_pipeline" "$LAMBDA_FUNCTION_NAME" "Lambda function"

# Import Lambda permission
echo ""
echo -e "${CYAN}=== Importing Lambda Permission ===${NC}"
LAMBDA_PERMISSION_ID="${LAMBDA_FUNCTION_NAME}/AllowExecutionFromS3Bucket"
import_resource "aws_lambda_permission.s3_invoke_lambda" "$LAMBDA_PERMISSION_ID" "Lambda permission for S3"

# Import S3 bucket notification
echo ""
echo -e "${CYAN}=== Importing S3 Bucket Notification ===${NC}"
if [ -n "$SOURCE_BUCKET" ]; then
    import_resource "aws_s3_bucket_notification.source_bucket_notification" "$SOURCE_BUCKET" "S3 bucket notification"
else
    echo -e "${YELLOW}Skipping S3 bucket notification (SOURCE_BUCKET not set)${NC}"
fi

# Import CloudWatch log group
if [ "$ENABLE_CLOUDWATCH" = "true" ]; then
    echo ""
    echo -e "${CYAN}=== Importing CloudWatch Log Group ===${NC}"
    import_resource "aws_cloudwatch_log_group.etl_pipeline[0]" "$LOG_GROUP_NAME" "CloudWatch log group"
else
    echo ""
    echo -e "${YELLOW}Skipping CloudWatch log group (CLOUDWATCH_ENABLED is not true)${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Import Process Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "1. Run: terraform plan"
echo "2. Review any differences between AWS and Terraform config"
echo "3. Update Terraform config if needed to match actual AWS resources"
echo "4. Run: terraform apply (if changes are needed)"
echo ""
echo -e "${YELLOW}Note: Some resources like IAM policy attachments may need to be imported separately${NC}"
echo ""