# PowerShell setup script for ETL Pipeline (Windows)

Write-Host "Setting up ETL Pipeline..." -ForegroundColor Green

# Check Python version
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python version: $pythonVersion" -ForegroundColor Cyan
} catch {
    Write-Host "Error: Python not found. Please install Python 3.9+" -ForegroundColor Red
    exit 1
}

# Check Java
try {
    $javaVersion = java -version 2>&1 | Select-Object -First 1
    Write-Host "Java version: $javaVersion" -ForegroundColor Cyan
} catch {
    Write-Host "Warning: Java not found. PySpark requires Java 11+" -ForegroundColor Yellow
    Write-Host "Download from: https://adoptium.net/" -ForegroundColor Yellow
}

# Create virtual environment
if (-not (Test-Path "venv")) {
    Write-Host "Creating virtual environment..." -ForegroundColor Cyan
    python -m venv venv
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Cyan
& .\venv\Scripts\Activate.ps1

# Install dependencies
Write-Host "Installing Python dependencies..." -ForegroundColor Cyan
python -m pip install --upgrade pip
pip install -r requirements.txt

# Create directories
New-Item -ItemType Directory -Force -Path "data" | Out-Null
New-Item -ItemType Directory -Force -Path "logs" | Out-Null
New-Item -ItemType Directory -Force -Path "lambda_package" | Out-Null

# Check AWS credentials
if (-not $env:AWS_ACCESS_KEY_ID -or -not $env:AWS_SECRET_ACCESS_KEY) {
    Write-Host "Warning: AWS credentials not set in environment" -ForegroundColor Yellow
    Write-Host "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY" -ForegroundColor Yellow
} else {
    Write-Host "AWS credentials found" -ForegroundColor Green
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Configure AWS credentials"
Write-Host "2. Deploy infrastructure: cd terraform; terraform init; terraform apply"
Write-Host "3. Upload a CSV file to the source S3 bucket (input/ prefix) to trigger the pipeline"
Write-Host "4. Or run locally: python etl_pipeline.py"

