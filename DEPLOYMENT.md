# Deployment Guide

This guide explains how to deploy and use the S3-triggered ETL pipeline.

## Overview

The pipeline is automatically triggered when you upload a CSV file to the source S3 bucket. The Lambda function processes the file and stores the results as Parquet in the destination bucket.

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

This creates the `lambda_package/` directory with all required files.

### 2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

The Terraform deployment will:
- Create source and destination S3 buckets
- Create Lambda function
- Set up S3 event notification (triggers on CSV uploads to `input/` prefix)
- Configure IAM roles and permissions
- Set up CloudWatch logging

### 3. Get Bucket Names

After deployment, get the bucket names:

```bash
cd terraform
terraform output source_bucket_name
terraform output destination_bucket_name
terraform output lambda_function_name
```

### 4. Upload CSV File

Upload your CSV file to trigger the pipeline:

```bash
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
aws s3 cp your_financial_data.csv s3://$SOURCE_BUCKET/input/your_financial_data.csv
```

**Important:** Files must be uploaded to the `input/` prefix and have a `.csv` extension to trigger the Lambda function.

### 5. Monitor Execution

**View CloudWatch Logs:**
```bash
aws logs tail /aws/lambda/etl-pipeline-etl-dev --follow
```

**Check Processed Data:**
```bash
DEST_BUCKET=$(terraform output -raw destination_bucket_name)
aws s3 ls s3://$DEST_BUCKET/processed_data/ --recursive
```

## Lambda Function Details

- **Runtime:** Python 3.9
- **Timeout:** 15 minutes (900 seconds)
- **Memory:** 3008 MB (maximum)
- **Trigger:** S3 ObjectCreated events on CSV files in `input/` prefix

## S3 Event Configuration

The Lambda function is triggered by:
- **Event:** `s3:ObjectCreated:*` (any object creation)
- **Prefix:** `input/`
- **Suffix:** `.csv`

## Troubleshooting

### Lambda Not Triggering

1. Check S3 event notification:
   ```bash
   aws s3api get-bucket-notification-configuration --bucket <source-bucket-name>
   ```

2. Verify file is in `input/` prefix with `.csv` extension

3. Check Lambda permissions:
   ```bash
   aws lambda get-policy --function-name <function-name>
   ```

### Lambda Timeout

If processing large files, consider:
- Using AWS Glue or EMR for larger datasets
- Increasing Lambda timeout (max 15 minutes)
- Splitting large files into smaller chunks

### View Lambda Logs

```bash
aws logs tail /aws/lambda/<function-name> --follow
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

## Manual Lambda Invocation (Testing)

You can manually invoke the Lambda function for testing:

```bash
aws lambda invoke \
  --function-name <function-name> \
  --payload '{"Records":[{"eventSource":"aws:s3","s3":{"bucket":{"name":"your-bucket"},"object":{"key":"input/test.csv"}}}]}' \
  response.json
```

## Cleanup

To remove all resources:

```bash
cd terraform
terraform destroy
```

## Next Steps

- Set up CloudWatch alarms for errors
- Configure SNS notifications for pipeline completion
- Add data validation rules
- Implement retry logic for failed processing

