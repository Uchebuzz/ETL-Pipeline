# Quick Start Guide

Get up and running with the ETL pipeline in 5 minutes!

## 1. Install Dependencies

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install packages
pip install -r requirements.txt
```

## 2. Set AWS Credentials & Deploy Infrastructure

Create a `.env` file in the project root with your AWS credentials:

```bash
# Create .env file
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_REGION=us-east-1
```

Then deploy the infrastructure:

```bash
cd terraform
../scripts/import_existing_resources.sh 
./terraform.sh init
./terraform.sh apply
```

This creates:
- Source S3 bucket (for uploading CSV files)
- Destination S3 bucket (for processed Parquet files)
- S3 bucket for Glue scripts
- AWS Glue job (PySpark ETL processing)
- Lambda function (automatically triggered on CSV upload)
- IAM roles and permissions
- CloudWatch logging

## 3. Upload CSV File to Trigger Pipeline

```bash
# Get the source bucket name from terraform output
cd terraform
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
cd ..

# Upload your CSV file using Python script
python scripts/upload_to_s3.py --bucket $SOURCE_BUCKET --file your_financial_data.csv
```

**That's it!** The pipeline automatically:
- Lambda detects the CSV upload
- Lambda triggers AWS Glue job
- Glue processes data with PySpark
- Transforms and cleans the data
- Loads as Parquet to the destination bucket

## 4. Check Results

Monitor the pipeline execution and view logs:

```bash
python scripts/monitor_pipeline.py
```

This will show:
- Lambda function logs
- Glue job status and execution details
- Processed files in the destination S3 bucket

## What's Next?

- Read [README.md](README.md) for detailed documentation
- Check [SETUP_GUIDE.md](SETUP_GUIDE.md) for comprehensive setup
- Review [DEPLOYMENT.md](DEPLOYMENT.md) for deployment details
- Review `terraform/` for infrastructure options
- See `.github/workflows/` for CI/CD setup
