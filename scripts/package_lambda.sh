#!/bin/bash
# Package Lambda function for deployment

set -e

echo "Packaging Lambda function..."

# Create lambda_package directory
mkdir -p lambda_package
rm -rf lambda_package/*

# Copy Python files
cp etl_pipeline.py lambda_package/
cp lambda_handler.py lambda_package/
cp config.py lambda_package/

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt -t lambda_package/ --upgrade

# Remove unnecessary files to reduce package size
find lambda_package -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type f -name "*.pyc" -delete
find lambda_package -type f -name "*.pyo" -delete
find lambda_package -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true

echo "Lambda package created in lambda_package/"
echo "Package size:"
du -sh lambda_package/

