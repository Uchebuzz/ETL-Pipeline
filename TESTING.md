# Testing and Verification Guide

This guide shows you how to verify that your ETL pipeline is working correctly.

## 1. Verify Infrastructure Deployment

### Check Terraform Outputs
```bash
cd terraform
terraform output
```

This shows:
- Source bucket name
- Destination bucket name
- Lambda function name
- Lambda function ARN

### Verify Resources in AWS Console
- **S3**: Check that source and destination buckets exist
- **Lambda**: Verify the function is deployed
- **IAM**: Check that roles and policies are created
- **CloudWatch**: Verify log groups exist

## 2. Test Lambda Function Manually

### Invoke Lambda Function with Test Event
```bash
# Get function name
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# Create test event
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{
    "Records": [{
      "eventSource": "aws:s3",
      "s3": {
        "bucket": {"name": "your-source-bucket"},
        "object": {"key": "input/test.csv"}
      }
    }]
  }' \
  response.json

# Check response
cat response.json
```

### Check Lambda Function Status
```bash
aws lambda get-function --function-name $FUNCTION_NAME
```

## 3. Test with Real CSV File

### Step 1: Prepare a Test CSV File
Create a test file `test_data.csv`:
```csv
Transaction ID,Date,Transaction Type,Category,Amount,Currency,Account ID,Description,Status
TXN-000001,2024-01-15,Purchase,Retail,1500.00,USD,ACC-1234,Test transaction 1,Completed
TXN-000002,2024-01-16,Sale,Technology,2500.00,USD,ACC-1234,Test transaction 2,Completed
```

### Step 2: Upload to S3 Source Bucket
```bash
# Get source bucket name
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)

# Upload test file
aws s3 cp test_data.csv s3://$SOURCE_BUCKET/input/test_data.csv
```

### Step 3: Check if Lambda Triggered
```bash
# Check Lambda logs (wait a few seconds after upload)
FUNCTION_NAME=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$FUNCTION_NAME --follow
```

### Step 4: Verify Output in Destination Bucket
```bash
# Get destination bucket name
DEST_BUCKET=$(terraform output -raw destination_bucket_name)

# List processed files
aws s3 ls s3://$DEST_BUCKET/processed_data/ --recursive

# Download and inspect output
aws s3 cp s3://$DEST_BUCKET/processed_data/date=*/data.parquet ./output.parquet
```

## 4. Monitor CloudWatch Logs

### View Lambda Logs
```bash
FUNCTION_NAME=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$FUNCTION_NAME --follow
```

### View Custom Log Group
```bash
LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)
aws logs tail $LOG_GROUP --follow
```

### Check for Errors
```bash
# Filter for errors only
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --filter-pattern "ERROR"
```

## 5. Test Pipeline Locally

### Run ETL Pipeline Locally
```bash
# Set environment variables
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export SOURCE_PATH=test_data.csv
export SOURCE_TYPE=local
export DESTINATION_BUCKET=your-destination-bucket

# Run pipeline
python etl_pipeline.py
```

### Test with S3 Source
```bash
export SOURCE_PATH=s3://your-source-bucket/input/test_data.csv
export SOURCE_TYPE=s3
python etl_pipeline.py
```

## 6. Check for Common Issues

### Issue: Lambda Not Triggering
```bash
# Check S3 event notification
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
aws s3api get-bucket-notification-configuration --bucket $SOURCE_BUCKET

# Check Lambda permissions
FUNCTION_NAME=$(terraform output -raw lambda_function_name)
aws lambda get-policy --function-name $FUNCTION_NAME
```

### Issue: Lambda Timeout
```bash
# Check Lambda configuration
aws lambda get-function-configuration --function-name $FUNCTION_NAME

# Increase timeout if needed (update in terraform/lambda.tf)
```

### Issue: Permission Errors
```bash
# Test IAM role permissions
aws iam get-role-policy \
  --role-name etl-pipeline-lambda-role-dev \
  --policy-name etl-pipeline-lambda-s3-policy-dev
```

### Issue: Package Too Large
```bash
# Check package size
cd terraform
ls -lh lambda_function.zip
ls -lh lambda_layer.zip
```

## 7. Verify Data Transformation

### Check Parquet File Contents
```python
import pandas as pd
import pyarrow.parquet as pq

# Read Parquet file
df = pd.read_parquet('output.parquet')
print(df.head())
print(df.info())
print(df.describe())
```

## 8. Monitor Metrics

### Check Lambda Metrics
```bash
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# Get invocation count
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum

# Get error count
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

## 9. Quick Health Check Script

Create a script `check_pipeline.sh`:
```bash
#!/bin/bash
echo "=== ETL Pipeline Health Check ==="

# Check Terraform state
echo "1. Checking Terraform outputs..."
cd terraform
terraform output > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Terraform outputs available"
else
    echo "✗ Terraform not deployed"
    exit 1
fi

# Check S3 buckets
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
DEST_BUCKET=$(terraform output -raw destination_bucket_name)

echo "2. Checking S3 buckets..."
aws s3 ls s3://$SOURCE_BUCKET > /dev/null 2>&1 && echo "✓ Source bucket exists" || echo "✗ Source bucket missing"
aws s3 ls s3://$DEST_BUCKET > /dev/null 2>&1 && echo "✓ Destination bucket exists" || echo "✗ Destination bucket missing"

# Check Lambda function
FUNCTION_NAME=$(terraform output -raw lambda_function_name)
echo "3. Checking Lambda function..."
aws lambda get-function --function-name $FUNCTION_NAME > /dev/null 2>&1 && echo "✓ Lambda function exists" || echo "✗ Lambda function missing"

# Check recent logs
echo "4. Checking recent Lambda logs..."
aws logs tail /aws/lambda/$FUNCTION_NAME --since 1h --format short | tail -5

echo "=== Health Check Complete ==="
```

## 10. Expected Behavior

### Successful Pipeline Run Should:
1. ✅ Upload CSV to source bucket triggers Lambda
2. ✅ Lambda processes the file (check logs)
3. ✅ Parquet file appears in destination bucket
4. ✅ No errors in CloudWatch logs
5. ✅ Data is transformed correctly (check Parquet contents)

### Signs of Issues:
- ❌ Lambda not triggering after upload
- ❌ Errors in CloudWatch logs
- ❌ No output files in destination bucket
- ❌ Lambda timeout errors
- ❌ Permission denied errors

## Troubleshooting Checklist

- [ ] Terraform apply completed successfully
- [ ] S3 buckets exist and are accessible
- [ ] Lambda function is deployed
- [ ] Lambda has correct IAM permissions
- [ ] S3 event notification is configured
- [ ] Lambda Layer is attached
- [ ] CloudWatch log group exists
- [ ] Test CSV file uploaded to correct prefix (`input/`)
- [ ] File has `.csv` extension
- [ ] AWS credentials are valid

## Next Steps

Once verified working:
1. Upload your actual financial data CSV files
2. Monitor CloudWatch logs for processing
3. Set up CloudWatch alarms for errors
4. Configure SNS notifications for completion
5. Schedule regular data uploads (if needed)

