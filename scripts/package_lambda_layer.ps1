# PowerShell script to package Lambda Layer with heavy dependencies

Write-Host "Packaging Lambda Layer (heavy dependencies)..." -ForegroundColor Green

# Create lambda_layer directory
if (Test-Path "lambda_layer") {
    Remove-Item -Recurse -Force "lambda_layer"
}
New-Item -ItemType Directory -Path "lambda_layer\python" | Out-Null

# Install only heavy dependencies to the layer
Write-Host "Installing heavy dependencies to layer..." -ForegroundColor Cyan
pip install pandas numpy pyarrow -t lambda_layer\python\ --upgrade

# Aggressively remove unnecessary files
Write-Host "Cleaning up unnecessary files..." -ForegroundColor Cyan

# Remove Python cache and compiled files
Get-ChildItem -Path "lambda_layer" -Recurse -Include "__pycache__" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_layer" -Recurse -Include "*.pyc" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_layer" -Recurse -Include "*.pyo" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_layer" -Recurse -Include "*.pyi" | Remove-Item -Force -ErrorAction SilentlyContinue

# Remove metadata directories
Get-ChildItem -Path "lambda_layer" -Recurse -Directory | Where-Object { $_.Name -like "*.dist-info" -or $_.Name -like "*.egg-info" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Remove test directories and files
Get-ChildItem -Path "lambda_layer" -Recurse -Directory | Where-Object { $_.Name -eq "tests" -or $_.Name -eq "test" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "lambda_layer" -Recurse -Include "*test*.py" | Remove-Item -Force -ErrorAction SilentlyContinue

# Remove documentation files
Get-ChildItem -Path "lambda_layer" -Recurse -Include "*.md", "*.txt", "*.rst", "*.html", "LICENSE", "LICENSE.txt" | Remove-Item -Force -ErrorAction SilentlyContinue

# Remove example and sample files
Get-ChildItem -Path "lambda_layer" -Recurse -Directory | Where-Object { $_.Name -eq "examples" -or $_.Name -eq "example" -or $_.Name -eq "samples" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Remove documentation directories
Get-ChildItem -Path "lambda_layer" -Recurse -Directory | Where-Object { $_.Name -eq "docs" -or $_.Name -eq "doc" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Lambda Layer package created in lambda_layer\" -ForegroundColor Green
$size = (Get-ChildItem -Path "lambda_layer" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Layer size: $([math]::Round($size, 2)) MB" -ForegroundColor Cyan

