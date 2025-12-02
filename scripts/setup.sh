#!/bin/bash
# Setup script for ETL Pipeline

set -e

echo "Setting up ETL Pipeline..."

# Check Python version
python_version=$(python3 --version 2>&1 | awk '{print $2}')
echo "Python version: $python_version"

# Java no longer required (using pandas instead of PySpark)

# Create virtual environment
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create data directory
mkdir -p data
mkdir -p logs
mkdir -p lambda_package

# Check AWS credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Warning: AWS credentials not set in environment"
    echo "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
else
    echo "AWS credentials found"
fi

echo "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Configure AWS credentials"
echo "2. Deploy infrastructure: cd terraform && terraform init && terraform apply"
echo "3. Upload a CSV file to the source S3 bucket (input/ prefix) to trigger the pipeline"
echo "4. Or run locally: python etl_pipeline.py"

