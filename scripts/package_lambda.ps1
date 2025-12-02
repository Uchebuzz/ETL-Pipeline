# PowerShell script to package Lambda function for deployment

Write-Host "Packaging Lambda function..." -ForegroundColor Green

# Create lambda_package directory
if (Test-Path "lambda_package") {
    Remove-Item -Recurse -Force "lambda_package"
}
New-Item -ItemType Directory -Path "lambda_package" | Out-Null

# Copy Python files
Copy-Item "etl_pipeline.py" -Destination "lambda_package\"
Copy-Item "lambda_handler.py" -Destination "lambda_package\"
Copy-Item "config.py" -Destination "lambda_package\"

# Install only lightweight dependencies (heavy deps go in Lambda Layer)
Write-Host "Installing lightweight dependencies..." -ForegroundColor Cyan
# Only install boto3, botocore, watchtower - pandas/numpy/pyarrow go in layer
pip install boto3 botocore watchtower -t lambda_package\ --upgrade

# Aggressively remove unnecessary files to reduce package size
Write-Host "Cleaning up unnecessary files..." -ForegroundColor Cyan

# Remove Python cache and compiled files
Get-ChildItem -Path "lambda_package" -Recurse -Include "__pycache__" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_package" -Recurse -Include "*.pyc" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_package" -Recurse -Include "*.pyo" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_package" -Recurse -Include "*.pyi" | Remove-Item -Force -ErrorAction SilentlyContinue

# Remove metadata directories
Get-ChildItem -Path "lambda_package" -Recurse -Directory | Where-Object { $_.Name -like "*.dist-info" -or $_.Name -like "*.egg-info" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Remove test directories and files
Get-ChildItem -Path "lambda_package" -Recurse -Directory | Where-Object { $_.Name -eq "tests" -or $_.Name -eq "test" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_package" -Recurse -Include "*test*.py" | Remove-Item -Force -ErrorAction SilentlyContinue

# Remove documentation files
Get-ChildItem -Path "lambda_package" -Recurse -Include "*.md", "*.txt", "*.rst", "*.html", "LICENSE", "LICENSE.txt" | Remove-Item -Force -ErrorAction SilentlyContinue

# Remove example and sample files
Get-ChildItem -Path "lambda_package" -Recurse -Directory | Where-Object { $_.Name -eq "examples" -or $_.Name -eq "example" -or $_.Name -eq "samples" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Remove documentation directories
Get-ChildItem -Path "lambda_package" -Recurse -Directory | Where-Object { $_.Name -eq "docs" -or $_.Name -eq "doc" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Remove .so files that aren't needed (keep only essential compiled extensions)
# This is more aggressive - be careful
Get-ChildItem -Path "lambda_package" -Recurse -Include "*.so.*" | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "Lambda package created in lambda_package\" -ForegroundColor Green
$size = (Get-ChildItem -Path "lambda_package" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Package size: $([math]::Round($size, 2)) MB" -ForegroundColor Cyan

