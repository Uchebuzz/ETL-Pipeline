# Quick Start Guide

Get up and running with the ETL pipeline in 5 minutes!

## 1. Install Dependencies

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# Install packages
pip install -r requirements.txt
```

## 2. Set AWS Credentials & Deploy Infrastructure

Create a `.env` file in the project root using `.env.example` as a template. Update the file with your AWS credentials, S3 bucket names, and CloudWatch configuration as shown in `.env.example`.

Then deploy the infrastructure:

```bash
scripts/package_lambda.sh
cd terraform 
./terraform.sh init
../scripts/import_existing_resources.sh
./terraform.sh apply
```

You can deploy using PowerShell as well (Windows):

```powershell
scripts\package_lambda.ps1
cd terraform
.\terraform.ps1 init
..\scripts\import_existing_resources.ps1
.\terraform.ps1 apply
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

Note: Please ensure you are on the project directory

```bash
# Get the source bucket name from terraform output
cd terraform
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
cd ..

# Upload your CSV file using Python script
python scripts/upload_to_s3.py --bucket $SOURCE_BUCKET --file your_financial_data.csv
```

You can also use PowerShell to upload your CSV file on Windows:
```powershell
$source_bucket = (& .terraform\terraform.ps1 output -raw source_bucket_name)
cd ..
python scripts\upload_to_s3.py --bucket $source_bucket --file your_financial_data.csv
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
You can also monitor the pipeline execution using PowerShell:

```powershell
python scripts\monitor_pipeline.py --lambda-name Lambda-Function-Name --glue-job Glue-Job-Name --dest-bucket Dest-Bucket-Name
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
