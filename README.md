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

For a quick setup guide, see [QUICK_START.md](QUICK_START.md).

The quick start guide covers:
- Installing dependencies
- Setting up AWS credentials
- Deploying infrastructure with Terraform
- Uploading CSV files to trigger the pipeline
- Monitoring pipeline execution


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

The pipeline includes a simple GitHub Actions workflow that:

1. **Tests**: Runs linting checks
2. **Validates**: Validates Terraform configuration
3. **Deploys**: Automatically deploys infrastructure to AWS on pushes to `main` branch

### Setting up GitHub Secrets

Configure the following secrets in your GitHub repository:

- `AWS_ACCESS_KEY_ID` - Required for deployment
- `AWS_SECRET_ACCESS_KEY` - Required for deployment
- `SOURCE_BUCKET_NAME` (optional) - Defaults to `etl-pipeline-source-dev`
- `DESTINATION_BUCKET_NAME` (optional) - Defaults to `etl-pipeline-dest-dev`

The workflow triggers on:
- Push to `main` branch (runs tests, validation, and deployment)
- Pull requests to `main` (runs tests and validation only)

## Monitoring

### CloudWatch Integration

The pipeline automatically logs to CloudWatch:

- **Lambda Log Group**: `/aws/lambda/etl-pipeline-etl-{env}`
- **Glue Log Group**: `/aws-glue/jobs/output`
- **Metrics**: Job start, completion, errors, duration, records processed
- **Alarms**: Error threshold monitoring

## Project Structure

```
ETL_Pipeline/
├── glue_etl_job.py          # AWS Glue ETL script (PySpark)
├── lambda_handler.py        # Lambda handler (triggers Glue)
├── requirements.txt         # Python dependencies
├── README.md                # Project documentation
├── QUICK_START.md           # Quick start guide
├── .github/
│   └── workflows/
│       └── etl-pipeline.yml # GitHub Actions CI/CD workflow
├── terraform/
│   ├── main.tf             # Terraform main configuration
│   ├── variables.tf        # Variable definitions
│   ├── s3.tf               # S3 bucket resources
│   ├── lambda.tf           # Lambda function & IAM roles
│   ├── glue.tf             # AWS Glue job resources
│   ├── cloudwatch.tf       # CloudWatch resources
│   └── terraform.ps1       # PowerShell Terraform wrapper
├── scripts/
│   ├── monitor_pipeline.py # Monitor pipeline execution
│   ├── upload_to_s3.py     # Upload files to S3
│   ├── package_lambda.sh   # Package Lambda (Linux/Mac)
│   ├── package_lambda.ps1  # Package Lambda (Windows)
│   └── setup.ps1           # Setup script (Windows)
├── monitoring/
│   └── cloudwatch_setup.py # CloudWatch monitoring utilities
├── lambda_package/          # Lambda package directory (generated)
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