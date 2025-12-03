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
- S3 bucket for Glue scripts
- AWS Glue job (PySpark ETL processing)
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

**That's it!** The pipeline automatically:
- Lambda detects the CSV upload
- Lambda triggers AWS Glue job
- Glue processes data with PySpark
- Transforms and cleans the data
- Loads as Parquet to the destination bucket

## Check Results

```bash
# View processed data
DEST_BUCKET=$(terraform output -raw destination_bucket_name)
aws s3 ls s3://$DEST_BUCKET/processed_data/ --recursive

# View Lambda logs
LAMBDA_NAME=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$LAMBDA_NAME --follow

# View Glue job status
GLUE_JOB=$(terraform output -raw glue_job_name)
aws glue get-job-runs --job-name $GLUE_JOB --max-items 1
```

## What's Next?

- Read [README.md](README.md) for detailed documentation
- Check [SETUP_GUIDE.md](SETUP_GUIDE.md) for comprehensive setup
- Review [DEPLOYMENT.md](DEPLOYMENT.md) for deployment details
- Review `terraform/` for infrastructure options
- See `.github/workflows/` for CI/CD setup
