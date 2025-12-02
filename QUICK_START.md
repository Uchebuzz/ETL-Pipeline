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

## 2. Set AWS Credentials

```bash
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
```

## 3. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates:
- Source S3 bucket (for uploading CSV files)
- Destination S3 bucket (for processed Parquet files)
- Lambda function (automatically triggered on CSV upload)
- IAM roles and permissions
- CloudWatch logging

## 4. Upload CSV File to Trigger Pipeline

```bash
# Get the source bucket name
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)

# Upload your CSV file to the input/ prefix
aws s3 cp your_financial_data.csv s3://$SOURCE_BUCKET/input/your_financial_data.csv
```

**That's it!** The Lambda function automatically:
- Detects the CSV upload
- Extracts data from S3
- Transforms and cleans the data
- Loads as Parquet to the destination bucket

## Check Results

```bash
# View processed data
DEST_BUCKET=$(terraform output -raw destination_bucket_name)
aws s3 ls s3://$DEST_BUCKET/processed_data/ --recursive

# View CloudWatch logs
aws logs tail /aws/etl-pipeline --follow
```

## Run Locally (Optional)

```bash
export SOURCE_PATH=s3://your-source-bucket/input/your_data.csv
export SOURCE_TYPE=s3
export DESTINATION_BUCKET=your-destination-bucket
python etl_pipeline.py
```

## Docker Quick Start

```bash
docker-compose up --build
```

## What's Next?

- Read [README.md](README.md) for detailed documentation
- Check [SETUP_GUIDE.md](SETUP_GUIDE.md) for comprehensive setup
- Review `terraform/` for infrastructure options
- See `.github/workflows/` for CI/CD setup

