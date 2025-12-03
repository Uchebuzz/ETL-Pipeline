# ETL Pipeline for Financial Data Processing

A serverless ETL (Extract, Transform, Load) pipeline for processing financial data using AWS Glue and Lambda. The pipeline automatically processes CSV files uploaded to S3 using PySpark for scalable data transformation.

## Features

- **Serverless Architecture**: AWS Glue handles Spark execution automatically
- **S3-Triggered Processing**: Lambda triggers Glue jobs on CSV uploads
- **PySpark Processing**: Scalable data transformation using Spark
- **Data Storage**: Outputs data in Parquet format to S3
- **Infrastructure as Code**: Terraform configuration for AWS resources
- **CI/CD**: GitHub Actions workflow for automated testing and deployment
- **Monitoring**: CloudWatch integration for logging and metrics

## Architecture

```
┌─────────────┐
│ Upload CSV  │ → S3 Source Bucket (input/ prefix)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ S3 Event    │ → Triggers Lambda Function
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Lambda    │ → Triggers AWS Glue Job
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ AWS Glue    │ → PySpark ETL Processing
│   (PySpark) │   - Extract from S3
│             │   - Transform data
│             │   - Load to S3 as Parquet
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ S3 Output   │ → Parquet files in destination bucket
└─────────────┘
```

## Prerequisites

- Python 3.9+
- AWS CLI configured with credentials
- Terraform 1.0+ (for infrastructure deployment)
- Docker (optional, for local testing)

## Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd ETL_Pipeline
   ```

2. **Create virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your AWS credentials
   ```

## Quick Start

### 1. Deploy Infrastructure with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates:
- Source and destination S3 buckets
- Lambda function (triggers Glue jobs)
- AWS Glue job (PySpark ETL processing)
- IAM roles and policies
- CloudWatch log groups
- S3 event notifications

### 2. Upload CSV File to Trigger Pipeline

Upload a CSV file to the source S3 bucket's `input/` prefix:

```bash
# Get the source bucket name from Terraform output
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)

# Upload your CSV file
aws s3 cp your_data.csv s3://$SOURCE_BUCKET/input/your_data.csv
```

The Lambda function will automatically trigger the Glue job to process the file!

### 3. Monitor Glue Job Execution

**View CloudWatch Logs:**
```bash
# Lambda logs
aws logs tail /aws/lambda/etl-pipeline-etl-dev --follow

# Glue job logs
aws logs tail /aws-glue/jobs/output --follow
```

**Check Processed Data:**
```bash
DEST_BUCKET=$(terraform output -raw destination_bucket_name)
aws s3 ls s3://$DEST_BUCKET/processed_data/ --recursive
```

**Check Glue Job Status:**
```bash
GLUE_JOB=$(terraform output -raw glue_job_name)
aws glue get-job-runs --job-name $GLUE_JOB --max-items 1
```


## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | AWS access key | Required |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | Required |
| `SOURCE_PATH` | Path to source data | `data/sample_financial_data.csv` |
| `SOURCE_TYPE` | Source type: `s3` or `local` | `local` |
| `DESTINATION_BUCKET` | S3 bucket for output | `etl-pipeline-output` |
| `OUTPUT_PREFIX` | S3 prefix for output | `processed_data` |
| `CLOUDWATCH_LOG_GROUP` | CloudWatch log group | `etl-pipeline` |
| `CLOUDWATCH_ENABLED` | Enable CloudWatch logging | `true` |

### Terraform Variables

Edit `terraform/variables.tf` or use `terraform.tfvars`:

```hcl
aws_region            = "us-east-1"
environment           = "dev"
project_name          = "etl-pipeline"
enable_cloudwatch     = true
```

### Glue Job Configuration

The Glue job is configured in `terraform/glue.tf`:
- **Glue Version**: 4.0
- **Worker Type**: G.1X (serverless)
- **Number of Workers**: 2
- **Timeout**: 60 minutes
- **Python Version**: 3

## CI/CD with GitHub Actions

The pipeline includes a GitHub Actions workflow that:

1. **Tests**: Runs linting and unit tests
2. **Validates**: Validates Terraform configuration
3. **Deploys**: Deploys infrastructure to AWS
4. **Executes**: Triggers Glue job for testing

### Setting up GitHub Secrets

Configure the following secrets in your GitHub repository:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `SOURCE_PATH` (optional)
- `DESTINATION_BUCKET` (optional)
- `CLOUDWATCH_LOG_GROUP` (optional)

The workflow triggers on:
- Push to `main` or `develop` branches
- Pull requests to `main`
- Manual workflow dispatch

## Monitoring

### CloudWatch Integration

The pipeline automatically logs to CloudWatch:

- **Lambda Log Group**: `/aws/lambda/etl-pipeline-etl-{env}`
- **Glue Log Group**: `/aws-glue/jobs/output`
- **Metrics**: Job start, completion, errors, duration, records processed
- **Alarms**: Error threshold monitoring

View logs:
```bash
# Lambda logs
aws logs tail /aws/lambda/etl-pipeline-etl-dev --follow

# Glue job logs
aws logs tail /aws-glue/jobs/output --follow
```


## Project Structure

```
ETL_Pipeline/
├── glue_etl_job.py          # AWS Glue ETL script (PySpark)
├── lambda_handler.py         # Lambda handler (triggers Glue)
├── requirements.txt          # Python dependencies
├── .github/
│   └── workflows/
│       └── etl-pipeline.yml  # GitHub Actions workflow
├── terraform/
│   ├── main.tf              # Terraform main configuration
│   ├── variables.tf         # Variable definitions
│   ├── s3.tf               # S3 bucket resources
│   ├── lambda.tf           # Lambda function resources
│   ├── glue.tf             # AWS Glue job resources
│   ├── iam.tf              # IAM roles and policies
│   ├── cloudwatch.tf       # CloudWatch resources
│   └── outputs.tf          # Output values
├── monitoring/
│   └── cloudwatch_setup.py # CloudWatch monitoring utilities
└── data/                    # Data directory (gitignored)
```

## Data Format

### Input Format (CSV)

```csv
Transaction ID,Date,Transaction Type,Category,Amount,Currency,Account ID,Description,Status
TXN-000001,2024-01-15,Purchase,Retail,1500.00,USD,ACC-1234,Sample transaction 1,Completed
```

### Output Format (Parquet)

Data is stored in Parquet format partitioned by date:
```
s3://bucket/processed_data/date=20240115_120000/
  ├── part-00000-xxx.snappy.parquet
  └── part-00001-xxx.snappy.parquet
```

## Troubleshooting

### Common Issues

1. **Glue Job Not Starting**
   - Check Lambda logs for errors
   - Verify Glue job name is correct
   - Check IAM permissions for Lambda to trigger Glue

2. **Glue Job Failing**
   - Check Glue job logs in CloudWatch
   - Verify S3 paths are correct
   - Check Glue script syntax

3. **AWS credentials not found**
   - Verify credentials are set: `aws configure list`
   - Check environment variables or Vault configuration

4. **S3 access denied**
   - Verify IAM permissions
   - Check bucket policies
   - Ensure bucket exists

5. **Lambda timeout**
   - Lambda only triggers Glue, timeout should be minimal (60 seconds)
   - Processing happens in Glue, not Lambda

## Testing

The ETL pipeline is tested through AWS Glue job execution. Monitor job runs and logs to verify functionality.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For issues and questions:
- Open an issue on GitHub
- Check the troubleshooting section
- Review AWS CloudWatch logs

## Next Steps

- Add data validation rules
- Implement data quality checks
- Add more transformation functions
- Set up scheduled runs (EventBridge/CloudWatch Events)
- Add data lineage tracking
- Implement incremental processing
