# ETL Pipeline for Financial Data Processing

A comprehensive ETL (Extract, Transform, Load) pipeline for processing financial data with AWS integration, automated CI/CD, and infrastructure as code.

## Features

- **Data Ingestion**: Supports CSV and JSON formats from S3 (automatically triggered on upload)
- **Data Transformation**: Uses PySpark for scalable data processing
- **Data Storage**: Outputs data in Parquet format to S3
- **Infrastructure as Code**: Terraform configuration for AWS resources
- **CI/CD**: GitHub Actions workflow for automated testing and deployment
- **Monitoring**: CloudWatch integration for logging and metrics
- **Secrets Management**: Support for environment variables and HashiCorp Vault
- **Containerization**: Docker and Docker Compose support

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
│   Extract   │ (PySpark from S3)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Transform   │ (Clean, Enrich, Aggregate)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Load     │ (Parquet to S3 Destination)
└─────────────┘
```

## Prerequisites

- Python 3.9+
- Java 11+ (required for PySpark)
- AWS CLI configured with credentials
- Terraform 1.0+ (for infrastructure deployment)
- Docker (optional, for containerized execution)

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
- Lambda function for S3-triggered processing
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

The Lambda function will automatically trigger and process the file!

### 3. Run ETL Pipeline Locally (Optional)

```bash
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export DESTINATION_BUCKET=your-bucket-name
export SOURCE_PATH=s3://your-source-bucket/input/your_data.csv
export SOURCE_TYPE=s3

python etl_pipeline.py
```

### 4. Run with Docker

```bash
docker-compose up --build
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
enable_ec2            = false
ec2_instance_type     = "t3.medium"
```

## CI/CD with GitHub Actions

The pipeline includes a GitHub Actions workflow that:

1. **Tests**: Runs linting and unit tests
2. **Validates**: Validates Terraform configuration
3. **Deploys**: Deploys infrastructure to AWS
4. **Executes**: Runs the ETL pipeline

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

The pipeline automatically logs to CloudWatch when enabled:

- **Log Group**: `etl-pipeline` (configurable)
- **Metrics**: Pipeline start, completion, errors, duration, records processed
- **Alarms**: Error threshold monitoring

View logs:
```bash
aws logs tail /aws/etl-pipeline --follow
```

### Local Logging

Logs are also written to console and can be redirected to files:

```bash
python etl_pipeline.py 2>&1 | tee logs/etl_$(date +%Y%m%d_%H%M%S).log
```

## Secrets Management

### Environment Variables (Default)

Store credentials in environment variables or `.env` file:

```bash
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
```

### HashiCorp Vault

1. Set environment variables:
   ```bash
   export VAULT_ADDR=https://your-vault-address
   export VAULT_TOKEN=your-vault-token
   export USE_VAULT=true
   ```

2. Store credentials in Vault:
   ```bash
   vault kv put aws/credentials \
     aws_access_key_id=your_key \
     aws_secret_access_key=your_secret
   ```

### AWS Secrets Manager

Alternatively, use AWS Secrets Manager (see `secrets/README.md` for details).

## Project Structure

```
ETL_Pipeline/
├── etl_pipeline.py          # Main ETL pipeline
├── data_generator.py         # Sample data generator
├── config.py                 # Configuration management
├── requirements.txt          # Python dependencies
├── Dockerfile                # Docker image definition
├── docker-compose.yml        # Docker Compose configuration
├── .github/
│   └── workflows/
│       └── etl-pipeline.yml  # GitHub Actions workflow
├── terraform/
│   ├── main.tf              # Terraform main configuration
│   ├── variables.tf         # Variable definitions
│   ├── s3.tf                # S3 bucket resources
│   ├── iam.tf               # IAM roles and policies
│   ├── cloudwatch.tf        # CloudWatch resources
│   ├── ec2.tf               # EC2 instance (optional)
│   └── outputs.tf           # Output values
├── monitoring/
│   └── cloudwatch_setup.py  # CloudWatch monitoring utilities
├── secrets/
│   └── README.md            # Secrets management documentation
└── data/                     # Data directory (gitignored)
```

## Data Format

### Input Format (CSV)

```csv
Transaction ID,Date,Transaction Type,Category,Amount,Currency,Account ID,Description,Status
TXN-000001,2024-01-15,Purchase,Retail,1500.00,USD,ACC-1234,Sample transaction 1,Completed
```

### Input Format (JSON)

```json
[
  {
    "transaction_id": "TXN-000001",
    "date": "2024-01-15",
    "transaction_type": "Purchase",
    "category": "Retail",
    "amount": 1500.00,
    "currency": "USD",
    "account_id": "ACC-1234",
    "description": "Sample transaction 1",
    "status": "Completed"
  }
]
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

1. **Java not found**
   - Install Java 11+: `sudo apt-get install openjdk-11-jdk`
   - Set `JAVA_HOME` environment variable

2. **AWS credentials not found**
   - Verify credentials are set: `aws configure list`
   - Check environment variables or Vault configuration

3. **S3 access denied**
   - Verify IAM permissions
   - Check bucket policies
   - Ensure bucket exists

4. **Spark out of memory**
   - Increase driver/executor memory in Spark config
   - Reduce data size or partition data

## Testing

Run tests (when test files are added):

```bash
pytest test_etl.py -v
```

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
