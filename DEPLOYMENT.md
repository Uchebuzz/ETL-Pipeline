# Deployment Guide

This guide explains how to deploy and use the S3-triggered ETL pipeline with AWS Glue.

## Overview

The pipeline uses a serverless architecture:
- **S3 Event** → Triggers **Lambda Function** → Triggers **AWS Glue Job** → Processes data with **PySpark** → Outputs to **S3**

When you upload a CSV file to the source S3 bucket, Lambda automatically triggers an AWS Glue job that processes the file using PySpark and stores the results as Parquet in the destination bucket.

## Deployment Steps

### 1. Package Lambda Function

Before deploying, package the Lambda function:

**Linux/Mac:**
```bash
chmod +x scripts/package_lambda.sh
./scripts/package_lambda.sh
```

**Windows:**
```powershell
.\scripts\package_lambda.ps1
```

This creates the `lambda_package/` directory with the Lambda handler (no heavy dependencies needed).

### 2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

The Terraform deployment will:
- Configure IAM roles and permissions
- Create source and destination S3 buckets
- Create S3 bucket for Glue scripts
- Upload Glue ETL script to S3
- Set up CloudWatch logging
- Create AWS Glue job
- Create Lambda function (triggers Glue jobs)
- Set up S3 event notification (triggers on CSV uploads to `input/` prefix)

### 3. Get Resource Names

After deployment, get the resource names:

```bash
cd terraform
terraform output source_bucket_name
terraform output destination_bucket_name
terraform output lambda_function_name
terraform output glue_job_name
terraform output glue_scripts_bucket
```

### 4. Upload Data File

Upload your CSV or JSON file to trigger the pipeline:

**CSV file:**
```bash
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
aws s3 cp your_financial_data.csv s3://$SOURCE_BUCKET/input/your_financial_data.csv
```

**JSON file:**
```bash
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
aws s3 cp your_financial_data.json s3://$SOURCE_BUCKET/input/your_financial_data.json
```

**Important:** Files must be uploaded to the `input/` prefix and have a `.csv` or `.json` extension to trigger the Lambda function.

### 5. Monitor Execution

**View Lambda Logs:**
```bash
LAMBDA_NAME=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$LAMBDA_NAME --follow
```

**View Glue Job Logs:**
```bash
GLUE_JOB=$(terraform output -raw glue_job_name)
aws logs tail /aws-glue/jobs/output --follow
```

**Check Glue Job Status:**
```bash
GLUE_JOB=$(terraform output -raw glue_job_name)
aws glue get-job-runs --job-name $GLUE_JOB --max-items 1
```

**Check Processed Data:**
```bash
DEST_BUCKET=$(terraform output -raw destination_bucket_name)
aws s3 ls s3://$DEST_BUCKET/processed_data/ --recursive
```

## Lambda Function Details

- **Runtime:** Python 3.9
- **Timeout:** 60 seconds (just triggers Glue)
- **Memory:** 128 MB (minimal, just triggers Glue)
- **Trigger:** S3 ObjectCreated events on CSV or JSON files in `input/` prefix
- **Function:** Triggers AWS Glue job with S3 file information

## AWS Glue Job Details

- **Glue Version:** 4.0
- **Worker Type:** G.1X (serverless)
- **Number of Workers:** 2
- **Timeout:** 60 minutes
- **Python Version:** 3
- **Script:** PySpark-based ETL processing
- **Processing:** Extracts CSV or JSON, transforms with Spark, outputs Parquet

## S3 Event Configuration

The Lambda function is triggered by:
- **Event:** `s3:ObjectCreated:*` (any object creation)
- **Prefix:** `input/`
- **Suffix:** `.csv` or `.json`

## Troubleshooting

### Lambda Not Triggering

1. Check S3 event notification:
   ```bash
   aws s3api get-bucket-notification-configuration --bucket <source-bucket-name>
   ```

2. Verify file is in `input/` prefix with `.csv` or `.json` extension

3. Check Lambda permissions:
   ```bash
   aws lambda get-policy --function-name <function-name>
   ```

### Glue Job Not Starting

1. Check Lambda logs for errors:
   ```bash
   aws logs tail /aws/lambda/<function-name> --follow
   ```

2. Verify Glue job exists:
   ```bash
   aws glue get-job --job-name <glue-job-name>
   ```

3. Check IAM permissions for Lambda to trigger Glue:
   ```bash
   aws iam get-role-policy --role-name <lambda-role> --policy-name <policy-name>
   ```

### Glue Job Failing

1. Check Glue job logs:
   ```bash
   aws logs tail /aws-glue/jobs/output --follow
   ```

2. Verify S3 paths in Glue script are correct

3. Check Glue script syntax:
   ```bash
   aws s3 cp s3://<glue-scripts-bucket>/scripts/glue_etl_job.py .
   python -m py_compile glue_etl_job.py
   ```

4. Verify Glue has S3 access permissions

### View Lambda Logs

```bash
aws logs tail /aws/lambda/<function-name> --follow
```

### View Glue Job Logs

```bash
aws logs tail /aws-glue/jobs/output --follow
```

## Updating Lambda Function

After code changes:

1. Package the Lambda function:
   ```bash
   ./scripts/package_lambda.sh
   ```

2. Update Terraform:
   ```bash
   cd terraform
   terraform apply
   ```

The Lambda function will be automatically updated.

## Updating Glue Job Script

After modifying `glue_etl_job.py`:

1. Upload updated script:
   ```bash
   aws s3 cp glue_etl_job.py s3://<glue-scripts-bucket>/scripts/glue_etl_job.py
   ```

2. Or update via Terraform:
   ```bash
   cd terraform
   terraform apply
   ```

The Glue script will be automatically uploaded to S3.

## Manual Lambda Invocation (Testing)

You can manually invoke the Lambda function for testing:

```bash
aws lambda invoke \
  --function-name <function-name> \
  --payload '{"Records":[{"eventSource":"aws:s3","s3":{"bucket":{"name":"your-bucket"},"object":{"key":"input/test.csv"}}}]}' \
  response.json
```

## Manual Glue Job Trigger (Testing)

You can manually trigger the Glue job:

```bash
aws glue start-job-run \
  --job-name <glue-job-name> \
  --arguments '{
    "--source_bucket": "your-source-bucket",
    "--source_key": "input/test.csv",
    "--destination_bucket": "your-destination-bucket",
    "--output_prefix": "processed_data"
  }'
```

## Cleanup

To remove all resources:

```bash
cd terraform
terraform destroy
```

**Note:** This will delete:
- S3 buckets (and all data)
- Lambda function
- Glue job
- IAM roles and policies
- CloudWatch log groups

## Cost Optimization

- **Lambda**: Pay per invocation (minimal cost, just triggers Glue)
- **Glue**: Pay per DPU-hour (serverless, scales automatically)
- **S3**: Pay for storage and requests
- **CloudWatch**: Pay for log storage and queries

For cost optimization:
- Use Glue job bookmarks for incremental processing
- Set appropriate Glue worker count based on data size
- Use S3 lifecycle policies for old data
- Archive CloudWatch logs after retention period

## Next Steps

- Set up CloudWatch alarms for errors
- Configure SNS notifications for pipeline completion
- Add data validation rules
- Implement retry logic for failed processing
- Set up Glue job bookmarks for incremental processing
- Configure Glue job monitoring and alerting
