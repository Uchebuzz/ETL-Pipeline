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
        
        # Map .env variables to Terraform variables
        case "$key" in
            SOURCE_BUCKET)
                tf_var_name="TF_VAR_source_bucket_name"
                ;;
            DESTINATION_BUCKET)
                tf_var_name="TF_VAR_destination_bucket_name"
                ;;
            GLUE_SCRIPTS_BUCKET_NAME)
                tf_var_name="TF_VAR_glue_scripts_bucket_name"
                ;;
            AWS_REGION)
                tf_var_name="TF_VAR_aws_region"
                ;;
            ENVIRONMENT)
                tf_var_name="TF_VAR_environment"
                ;;
            PROJECT_NAME)
                tf_var_name="TF_VAR_project_name"
                ;;
            CLOUDWATCH_ENABLED)
                tf_var_name="TF_VAR_enable_cloudwatch"
                ;;
            *)
                tf_var_name="$key"
                ;;
        esac
        
        # Export the variable (handle dynamic variable names)
        eval "export $(printf '%s=%q' "$tf_var_name" "$value")"
    done < "$ENV_FILE"
fi

# Run terraform command
terraform "$COMMAND" "$@"