#!/bin/bash
# Package Lambda Layer with heavy dependencies

set -e

echo "Packaging Lambda Layer (heavy dependencies)..."

# Create lambda_layer directory
mkdir -p lambda_layer/python
rm -rf lambda_layer/python/*

# Install only heavy dependencies to the layer
echo "Installing heavy dependencies to layer..."
pip install pandas numpy pyarrow -t lambda_layer/python/ --upgrade

# Aggressively remove unnecessary files
echo "Cleaning up unnecessary files..."

# Remove Python cache and compiled files
find lambda_layer -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find lambda_layer -type f -name "*.pyc" -delete
find lambda_layer -type f -name "*.pyo" -delete
find lambda_layer -type f -name "*.pyi" -delete

# Remove metadata directories
find lambda_layer -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find lambda_layer -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Remove test directories and files
find lambda_layer -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find lambda_layer -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
find lambda_layer -type f -name "*test*.py" -delete 2>/dev/null || true

# Remove documentation files
find lambda_layer -type f \( -name "*.md" -o -name "*.txt" -o -name "*.rst" -o -name "*.html" -o -name "LICENSE" -o -name "LICENSE.txt" \) -delete 2>/dev/null || true

# Remove example and sample directories
find lambda_layer -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true
find lambda_layer -type d -name "example" -exec rm -rf {} + 2>/dev/null || true
find lambda_layer -type d -name "samples" -exec rm -rf {} + 2>/dev/null || true

# Remove documentation directories
find lambda_layer -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
find lambda_layer -type d -name "doc" -exec rm -rf {} + 2>/dev/null || true

echo "Lambda Layer package created in lambda_layer/"
echo "Layer size:"
du -sh lambda_layer/

