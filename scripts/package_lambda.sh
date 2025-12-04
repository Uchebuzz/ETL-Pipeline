#!/bin/bash
# Package Lambda function for deployment

set -e

echo "Packaging Lambda function..."

# Create lambda_package directory
mkdir -p lambda_package
rm -rf lambda_package/*

# Copy Python files (Lambda only triggers Glue, no ETL code needed)
cp lambda_handler.py lambda_package/

# Install only lightweight dependencies (boto3 for Glue client)
echo "Installing lightweight dependencies..."
if command -v pip >/dev/null 2>&1; then
    pip install boto3 -t lambda_package/ --upgrade
else
    echo "Warning: pip not found. Skipping dependency installation."
    echo "boto3 should be available in Lambda runtime, but ensure it's included if needed."
fi

# Aggressively remove unnecessary files to reduce package size
echo "Cleaning up unnecessary files..."

# Remove Python cache and compiled files
find lambda_package -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type f -name "*.pyc" -delete
find lambda_package -type f -name "*.pyo" -delete
find lambda_package -type f -name "*.pyi" -delete

# Remove metadata directories
find lambda_package -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Remove test directories and files
find lambda_package -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type f -name "*test*.py" -delete 2>/dev/null || true

# Remove documentation files
find lambda_package -type f \( -name "*.md" -o -name "*.txt" -o -name "*.rst" -o -name "*.html" -o -name "LICENSE" -o -name "LICENSE.txt" \) -delete 2>/dev/null || true

# Remove example and sample directories
find lambda_package -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type d -name "example" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type d -name "samples" -exec rm -rf {} + 2>/dev/null || true

# Remove documentation directories
find lambda_package -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
find lambda_package -type d -name "doc" -exec rm -rf {} + 2>/dev/null || true

# Remove .so.* files (versioned shared libraries, keep .so files)
find lambda_package -type f -name "*.so.*" -delete 2>/dev/null || true

echo "Lambda package created in lambda_package/"
echo "Package size:"
du -sh lambda_package/

