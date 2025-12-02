#!/bin/bash
# Run ETL pipeline locally

set -e

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Set default environment variables if not set
export SOURCE_PATH=${SOURCE_PATH:-data/sample_financial_data.csv}
export SOURCE_TYPE=${SOURCE_TYPE:-local}
export DESTINATION_BUCKET=${DESTINATION_BUCKET:-etl-pipeline-output}
export OUTPUT_PREFIX=${OUTPUT_PREFIX:-processed_data}
export AWS_REGION=${AWS_REGION:-us-east-1}
export CLOUDWATCH_LOG_GROUP=${CLOUDWATCH_LOG_GROUP:-etl-pipeline}

# Check if source file exists
if [ ! -f "$SOURCE_PATH" ] && [ "$SOURCE_TYPE" = "local" ]; then
    echo "Error: Source file not found: $SOURCE_PATH"
    echo "Please provide a CSV file or set SOURCE_PATH to an S3 URI"
    exit 1
fi

# Run ETL pipeline
echo "Running ETL pipeline..."
python etl_pipeline.py

echo "ETL pipeline completed!"

