# S3 bucket for Glue scripts
resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${var.project_name}-glue-scripts-${var.environment}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-glue-scripts"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload Glue ETL script to S3
resource "aws_s3_object" "glue_etl_script" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/glue_etl_job.py"
  source = "${path.module}/../glue_etl_job.py"
  etag   = filemd5("${path.module}/../glue_etl_job.py")

  tags = {
    Name = "glue-etl-script"
  }
}

# IAM Role for Glue
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-glue-role"
  }
}

# Attach AWS managed policy for Glue service role
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# IAM Policy for Glue to access S3
resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "${var.project_name}-glue-s3-policy-${var.environment}"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*",
          aws_s3_bucket.destination.arn,
          "${aws_s3_bucket.destination.arn}/*",
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      }
    ]
  })
}

# IAM Policy for Glue to write CloudWatch Logs
resource "aws_iam_role_policy" "glue_cloudwatch_policy" {
  name = "${var.project_name}-glue-cloudwatch-policy-${var.environment}"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      }
    ]
  })
}

# AWS Glue Job
resource "aws_glue_job" "etl_job" {
  name     = "${var.project_name}-etl-job-${var.environment}"
  role_arn = aws_iam_role.glue_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.id}/${aws_s3_object.glue_etl_script.key}"
    python_version  = "3"
  }

  depends_on = [aws_s3_object.glue_etl_script]

  default_arguments = {
    "--job-language"      = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
    "--enable-metrics"    = "true"
    "--enable-continuous-cloudwatch-log" = "true"
  }

  max_retries       = 0
  timeout           = 60  # minutes
  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"

  tags = {
    Name = "${var.project_name}-glue-etl-job"
  }
}

# IAM Policy for Lambda to trigger Glue jobs
resource "aws_iam_role_policy" "lambda_glue_policy" {
  name = "${var.project_name}-lambda-glue-policy-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns"
        ]
        Resource = aws_glue_job.etl_job.arn
      }
    ]
  })
}

# Outputs
output "glue_job_name" {
  description = "Name of the Glue job"
  value       = aws_glue_job.etl_job.name
}

output "glue_job_arn" {
  description = "ARN of the Glue job"
  value       = aws_glue_job.etl_job.arn
}

output "glue_scripts_bucket" {
  description = "S3 bucket for Glue scripts"
  value       = aws_s3_bucket.glue_scripts.id
}

