# Terraform wrapper script that loads .env file and runs terraform commands
# Usage: .\terraform.ps1 [terraform-command] [args...]
# Example: .\terraform.ps1 plan
#          .\terraform.ps1 apply

param(
    [Parameter(Position=0)]
    [string]$Command = "plan",
    
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

# Get the root directory (parent of terraform directory)
$RootDir = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $RootDir ".env"

# Load .env file if it exists
if (Test-Path $EnvFile) {
    Write-Host "Loading environment variables from .env file..." -ForegroundColor Cyan
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            # Remove quotes if present
            $value = $value -replace '^["'']|["'']$', ''
            
            # Map .env variables to Terraform variables
            $tfVarName = switch ($key) {
                "SOURCE_BUCKET" { "TF_VAR_source_bucket_name" }
                "DESTINATION_BUCKET" { "TF_VAR_destination_bucket_name" }
                "GLUE_SCRIPTS_BUCKET_NAME" { "TF_VAR_glue_scripts_bucket_name" }
                "AWS_REGION" { "TF_VAR_aws_region" }
                "ENVIRONMENT" { "TF_VAR_environment" }
                "PROJECT_NAME" { "TF_VAR_project_name" }
                "ENABLE_CLOUDWATCH" { "TF_VAR_enable_cloudwatch" }
                default { $key }
            }
            
            [Environment]::SetEnvironmentVariable($tfVarName, $value, "Process")
            Write-Host "  Loaded: $key -> $tfVarName" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "Warning: .env file not found at $EnvFile" -ForegroundColor Yellow
    Write-Host "Terraform will use AWS credentials from environment or AWS CLI config" -ForegroundColor Yellow
}

# Verify AWS credentials are set
if (-not $env:AWS_ACCESS_KEY_ID -or -not $env:AWS_SECRET_ACCESS_KEY) {
    Write-Host "Warning: AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set" -ForegroundColor Yellow
    Write-Host "Terraform may fail if AWS credentials are not configured via AWS CLI" -ForegroundColor Yellow
} else {
    Write-Host "AWS credentials loaded successfully" -ForegroundColor Green
}

# Run terraform command
Write-Host "`nRunning: terraform $Command $($Args -join ' ')`n" -ForegroundColor Cyan
& terraform $Command @Args

