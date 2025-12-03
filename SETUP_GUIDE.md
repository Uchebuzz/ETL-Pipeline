# ETL Pipeline Setup Guide

This guide will help you set up and run the ETL pipeline step by step.

## Prerequisites Checklist

- [ ] Python 3.9+ installed
- [ ] AWS CLI configured
- [ ] AWS credentials with S3, Lambda, and Glue access
- [ ] Terraform 1.0+ (for infrastructure)
- [ ] Git (for version control)

## Step 1: Initial Setup

### On Linux/Mac:
```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### On Windows:
```powershell
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
python data_generator.py
```

### Manual Setup:
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Generate sample data (optional)
python data_generator.py
```

## Step 2: Configure AWS Credentials

### Option 1: Environment Variables
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-east-1
```

### Option 2: AWS CLI
```bash
aws configure
```

### Option 3: .env File
Create a `.env` file:
```bash
cp .env.example .env
# Edit .env with your credentials
```

## Step 3: Deploy Infrastructure

### Initialize Terraform
```bash
cd terraform
terraform init
```

### Review Plan
```bash
terraform plan
```

### Apply Infrastructure
```bash
terraform apply
```

This creates:
- Source S3 bucket
- Destination S3 bucket
- Glue scripts S3 bucket
- AWS Glue job
- Lambda function
- IAM roles and policies
- CloudWatch log groups

### Get Output Values
```bash
terraform output
```

Save these values for later use:
- `source_bucket_name`
- `destination_bucket_name`
- `lambda_function_name`
- `glue_job_name`

## Step 4: Run ETL Pipeline

### Automated (Recommended)

Upload a CSV file to trigger the pipeline:

```bash
# Get bucket name
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)

# Upload CSV file
aws s3 cp your_data.csv s3://$SOURCE_BUCKET/input/your_data.csv
```

The Lambda function will automatically trigger the Glue job!


## Step 5: Verify Results

### Check S3 Output
```bash
DEST_BUCKET=$(terraform output -raw destination_bucket_name)
aws s3 ls s3://$DEST_BUCKET/processed_data/ --recursive
```

### View Lambda Logs
```bash
LAMBDA_NAME=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$LAMBDA_NAME --follow
```

### View Glue Job Logs
```bash
aws logs tail /aws-glue/jobs/output --follow
```

### Check Glue Job Status
```bash
GLUE_JOB=$(terraform output -raw glue_job_name)
aws glue get-job-runs --job-name $GLUE_JOB --max-items 1
```

## Step 6: Set Up CI/CD (Optional)

### GitHub Actions Setup

1. **Fork/Clone Repository**
   ```bash
   git clone <your-repo-url>
   cd ETL_Pipeline
   ```

2. **Configure GitHub Secrets**
   - Go to Repository Settings → Secrets and variables → Actions
   - Add secrets:
     - `AWS_ACCESS_KEY_ID`
     - `AWS_SECRET_ACCESS_KEY`
     - `DESTINATION_BUCKET` (optional)
     - `CLOUDWATCH_LOG_GROUP` (optional)

3. **Push to GitHub**
   ```bash
   git add .
   git commit -m "Initial commit"
   git push origin main
   ```

4. **Workflow will run automatically** on push to main branch

## Troubleshooting

### Python Not Found
```bash
# Ubuntu/Debian
sudo apt-get install python3 python3-pip

# macOS
brew install python3

# Windows
# Download from python.org
```

### AWS Credentials Error
- Verify credentials: `aws sts get-caller-identity`
- Check IAM permissions (S3, Lambda, Glue access)
- Verify buckets exist and are accessible

### Lambda Not Triggering
- Check S3 event notification configuration
- Verify file is in `input/` prefix with `.csv` extension
- Check Lambda logs for errors

### Glue Job Not Starting
- Check Lambda logs for errors
- Verify Glue job exists and is accessible
- Check IAM permissions for Lambda to trigger Glue

### Glue Job Failing
- Check Glue job logs in CloudWatch
- Verify S3 paths are correct
- Check Glue script syntax
- Verify Glue has S3 access permissions

### Terraform Errors
- Run `terraform init` first
- Check AWS credentials
- Verify region is correct
- Check for resource name conflicts

## Architecture Overview

```
S3 Upload → Lambda Trigger → AWS Glue Job → S3 Output
```

- **S3**: Stores input CSV files and output Parquet files
- **Lambda**: Lightweight trigger (60s timeout, 128MB memory)
- **Glue**: Serverless Spark processing (scales automatically)
- **CloudWatch**: Logging and monitoring

## Next Steps

- [ ] Customize Glue transformation logic (`glue_etl_job.py`)
- [ ] Add data validation rules
- [ ] Set up scheduled runs (EventBridge)
- [ ] Configure alerts and notifications
- [ ] Add more data sources
- [ ] Implement incremental processing with Glue bookmarks
- [ ] Set up Glue job monitoring dashboards

## Getting Help

- Check README.md for detailed documentation
- Review DEPLOYMENT.md for deployment details
- Review CloudWatch logs for errors
- Check GitHub Issues
- Review AWS CloudWatch metrics
