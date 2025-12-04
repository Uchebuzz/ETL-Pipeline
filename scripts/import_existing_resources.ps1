# PowerShell script to import existing AWS resources into Terraform state

# Find terraform directory
$TerraformDir = $null
if (Test-Path "terraform.tf") {
    $TerraformDir = "."
} elseif (Test-Path "main.tf") {
    $TerraformDir = "."
} elseif (Test-Path "terraform\main.tf") {
    $TerraformDir = "terraform"
} else {
    Write-Host "Error: Could not find Terraform directory" -ForegroundColor Red
    exit 1
}

Set-Location $TerraformDir

# Ensure lambda_package directory exists (needed for data.archive_file.lambda_zip)
# Get root directory (parent of terraform directory, where lambda_handler.py is)
$RootDir = Split-Path -Parent (Get-Location)
$LambdaPackageDir = Join-Path $RootDir "lambda_package"
if (-not (Test-Path $LambdaPackageDir)) {
    New-Item -ItemType Directory -Path $LambdaPackageDir -Force | Out-Null
    $LambdaHandlerPath = Join-Path $RootDir "lambda_handler.py"
    if (Test-Path $LambdaHandlerPath) {
        Copy-Item $LambdaHandlerPath -Destination $LambdaPackageDir\
    } else {
        "# Placeholder" | Out-File -FilePath (Join-Path $LambdaPackageDir ".placeholder")
    }
}

# Get variables from environment or use defaults
$ProjectName = $env:TF_VAR_project_name
$Env = $env:TF_VAR_environment
$SourceBucket = $env:TF_VAR_source_bucket_name
$DestBucket = $env:TF_VAR_destination_bucket_name
$GlueScriptsBucket = $env:TF_VAR_glue_scripts_bucket_name

$LambdaRoleName = "${ProjectName}-lambda-role-${Env}"
$GlueRoleName = "${ProjectName}-glue-role-${Env}"
$LambdaFunctionName = "${ProjectName}-etl-${Env}"
$GlueJobName = "${ProjectName}-etl-job-${Env}"

Write-Host "`nImporting AWS resources into Terraform state..." -ForegroundColor Cyan
Write-Host "Project: $ProjectName" -ForegroundColor Gray
Write-Host "Environment: $Env`n" -ForegroundColor Gray

# Import IAM roles first (they don't have dependencies)
Write-Host "Importing IAM roles..." -ForegroundColor Yellow
& "terraform.exe" import aws_iam_role.lambda_role $LambdaRoleName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to import lambda_role" -ForegroundColor Red
}

& "terraform.exe" import aws_iam_role.glue_role $GlueRoleName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to import glue_role" -ForegroundColor Red
}

# Import Glue job (depends on glue_role)
Write-Host "`nImporting Glue job..." -ForegroundColor Yellow
& "terraform.exe" import aws_glue_job.etl_job $GlueJobName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to import glue_job" -ForegroundColor Red
}

# Import Lambda function (depends on lambda_role and data.archive_file)
Write-Host "`nImporting Lambda function..." -ForegroundColor Yellow
& "terraform.exe" import aws_lambda_function.etl_pipeline $LambdaFunctionName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to import lambda_function" -ForegroundColor Red
}

# Import Lambda permission
Write-Host "`nImporting Lambda permission..." -ForegroundColor Yellow
$LambdaPermissionId = "${LambdaFunctionName}/AllowExecutionFromS3Bucket"
& "terraform.exe" import aws_lambda_permission.s3_invoke_lambda $LambdaPermissionId
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to import lambda_permission" -ForegroundColor Red
}

# Import S3 buckets
Write-Host "`nImporting S3 buckets..." -ForegroundColor Yellow
if ($SourceBucket) {
    & "terraform.exe" import aws_s3_bucket.source $SourceBucket
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to import source bucket" -ForegroundColor Red
    }
} else {
    Write-Host "Skipping source bucket (TF_VAR_source_bucket_name not set)" -ForegroundColor Gray
}

if ($DestBucket) {
    & "terraform.exe" import aws_s3_bucket.destination $DestBucket
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to import destination bucket" -ForegroundColor Red
    }
} else {
    Write-Host "Skipping destination bucket (TF_VAR_destination_bucket_name not set)" -ForegroundColor Gray
}

& "terraform.exe" import aws_s3_bucket.glue_scripts $GlueScriptsBucket
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to import glue_scripts bucket" -ForegroundColor Red
}

# Import S3 bucket notification
Write-Host "`nImporting S3 bucket notification..." -ForegroundColor Yellow
if ($SourceBucket) {
    & "terraform.exe" import aws_s3_bucket_notification.source_bucket_notification $SourceBucket
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to import S3 bucket notification" -ForegroundColor Red
    }
} else {
    Write-Host "Skipping S3 bucket notification (TF_VAR_source_bucket_name not set)" -ForegroundColor Gray
}

# Import CloudWatch log group
$EnableCloudWatch = if ($env:TF_VAR_enable_cloudwatch) { 
    $env:TF_VAR_enable_cloudwatch 
} else { 
    "true" 
}

if ($EnableCloudWatch -eq "true") {
    Write-Host "`nImporting CloudWatch log group..." -ForegroundColor Yellow
    $LogGroupName = "${ProjectName}-${Env}"
    & "terraform.exe" import "aws_cloudwatch_log_group.etl_pipeline[0]" $LogGroupName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to import log group" -ForegroundColor Red
    }
}

Write-Host "`nImport process completed." -ForegroundColor Green

