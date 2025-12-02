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

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Cyan
pip install -r requirements.txt -t lambda_package\ --upgrade

# Remove unnecessary files
Get-ChildItem -Path "lambda_package" -Recurse -Include "__pycache__" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_package" -Recurse -Include "*.pyc" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_package" -Recurse -Include "*.pyo" | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "Lambda package created in lambda_package\" -ForegroundColor Green
$size = (Get-ChildItem -Path "lambda_package" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Package size: $([math]::Round($size, 2)) MB" -ForegroundColor Cyan

