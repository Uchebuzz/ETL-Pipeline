# ETL Pipeline Setup Guide

This guide will help you set up and run the ETL pipeline step by step.

## Prerequisites Checklist

- [ ] Python 3.9+ installed
- [ ] Python 3.9+ installed
- [ ] AWS CLI configured
- [ ] AWS credentials with S3 access
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

# Generate sample data
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

## Step 3: Deploy Infrastructure (Optional)

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
- IAM roles and policies
- CloudWatch log groups

### Get Output Values
```bash
terraform output
```

## Step 4: Run ETL Pipeline

### Local Execution
```bash
# Set environment variables
export SOURCE_PATH=data/sample_financial_data.csv
export SOURCE_TYPE=local
export DESTINATION_BUCKET=your-bucket-name

# Run pipeline
python etl_pipeline.py
```

### Using Helper Script
```bash
chmod +x scripts/run_local.sh
./scripts/run_local.sh
```

### From S3
```bash
# Upload data to S3 first
python scripts/upload_to_s3.py --bucket your-source-bucket --file data/sample_financial_data.csv

# Run pipeline
export SOURCE_PATH=s3://your-source-bucket/input/sample_financial_data.csv
export SOURCE_TYPE=s3
export DESTINATION_BUCKET=your-destination-bucket
python etl_pipeline.py
```

## Step 5: Verify Results

### Check S3 Output
```bash
aws s3 ls s3://your-destination-bucket/processed_data/ --recursive
```

### View CloudWatch Logs
```bash
aws logs tail /aws/etl-pipeline --follow
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

## Step 7: Docker Setup (Optional)

### Build Docker Image
```bash
docker build -t etl-pipeline .
```

### Run with Docker
```bash
docker run --rm \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e DESTINATION_BUCKET=your-bucket \
  -v $(pwd)/data:/app/data \
  etl-pipeline
```

### Docker Compose
```bash
docker-compose up --build
```

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
- Check IAM permissions
- Verify bucket exists and is accessible

### Memory Issues with Large Datasets
- Process data in chunks using pandas
- Consider using AWS Glue or EMR for very large datasets
- Increase Lambda memory if using Lambda

### Terraform Errors
- Run `terraform init` first
- Check AWS credentials
- Verify region is correct
- Check for resource name conflicts

## Next Steps

- [ ] Customize transformation logic
- [ ] Add data validation rules
- [ ] Set up scheduled runs
- [ ] Configure alerts
- [ ] Add more data sources
- [ ] Implement incremental processing

## Getting Help

- Check README.md for detailed documentation
- Review CloudWatch logs for errors
- Check GitHub Issues
- Review AWS CloudWatch metrics

