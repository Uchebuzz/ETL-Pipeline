#!/bin/bash
# Terraform wrapper script that loads .env file and runs terraform commands
# Usage: ./terraform.sh [terraform-command] [args...]
# Example: ./terraform.sh plan
#          ./terraform.sh apply

# Get the root directory (parent of terraform directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

# Default command is "plan" if no arguments provided
COMMAND="${1:-plan}"
shift  # Remove first argument, remaining args are for terraform

# Load .env file if it exists
if [ -f "$ENV_FILE" ]; then
    echo -e "\033[0;36mLoading environment variables from .env file...\033[0m"
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # Remove leading/trailing whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Skip if key is empty after trimming
        [[ -z "$key" ]] && continue
        
        # Remove quotes if present
        value=$(echo "$value" | sed -e 's/^["'\'']//' -e 's/["'\'']$//')
        
        # Map .env variables to Terraform variables
        case "$key" in
            "SOURCE_BUCKET")
                tf_var_name="TF_VAR_source_bucket_name"
                ;;
            "DESTINATION_BUCKET")
                tf_var_name="TF_VAR_destination_bucket_name"
                ;;
            "GLUE_SCRIPTS_BUCKET_NAME")
                tf_var_name="TF_VAR_glue_scripts_bucket_name"
                ;;
            "AWS_REGION")
                tf_var_name="TF_VAR_aws_region"
                ;;
            "ENVIRONMENT")
                tf_var_name="TF_VAR_environment"
                ;;
            "PROJECT_NAME")
                tf_var_name="TF_VAR_project_name"
                ;;
            "ENABLE_CLOUDWATCH")
                tf_var_name="TF_VAR_enable_cloudwatch"
                ;;
            *)
                tf_var_name="$key"
                ;;
        esac
        
        export "$tf_var_name=$value"
        echo -e "  \033[0;37mLoaded: $key -> $tf_var_name\033[0m"
    done < "$ENV_FILE"
else
    echo -e "\033[0;33mWarning: .env file not found at $ENV_FILE\033[0m"
    echo -e "\033[0;33mTerraform will use AWS credentials from environment or AWS CLI config\033[0m"
fi

# Verify AWS credentials are set
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "\033[0;33mWarning: AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set\033[0m"
    echo -e "\033[0;33mTerraform may fail if AWS credentials are not configured via AWS CLI\033[0m"
else
    echo -e "\033[0;32mAWS credentials loaded successfully\033[0m"
fi

# Run terraform command
echo -e "\n\033[0;36mRunning: terraform $COMMAND $*\033[0m\n"
terraform "$COMMAND" "$@"

