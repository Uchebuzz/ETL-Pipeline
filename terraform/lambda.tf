# Lambda function for triggering Glue jobs from S3 events
resource "aws_lambda_function" "etl_pipeline" {
  function_name = "${var.project_name}-etl-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.9"
  timeout       = 60  # 1 minute - just triggers Glue job
  memory_size   = 128 # Minimal memory needed

  # Package the Lambda function (code only, no heavy deps)
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      GLUE_JOB_NAME        = aws_glue_job.etl_job.name
      DESTINATION_BUCKET   = aws_s3_bucket.destination.id
      OUTPUT_PREFIX        = "processed_data"
      CLOUDWATCH_LOG_GROUP = var.enable_cloudwatch ? try(aws_cloudwatch_log_group.etl_pipeline[0].name, "/aws/lambda/${var.project_name}-etl-${var.environment}") : "/aws/lambda/${var.project_name}-etl-${var.environment}"
      CLOUDWATCH_ENABLED   = tostring(var.enable_cloudwatch)
    }
  }

  # Ensure Glue job exists before Lambda function
  depends_on = [
    aws_glue_job.etl_job
  ]

  tags = {
    Name = "${var.project_name}-etl-lambda"
  }
}

# Package Lambda function before deployment
resource "null_resource" "package_lambda" {
  triggers = {
    lambda_handler = filemd5("${path.module}/../lambda_handler.py")
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    interpreter = ["powershell.exe", "-Command"]
    command     = "if (Get-Command bash -ErrorAction SilentlyContinue) { bash scripts/package_lambda.sh } else { powershell.exe -ExecutionPolicy Bypass -File scripts/package_lambda.ps1 }"
  }
}

# Create deployment package
data "archive_file" "lambda_zip" {
  depends_on  = [null_resource.package_lambda]
  type        = "zip"
  source_dir  = "${path.module}/../lambda_package"
  output_path = "${path.module}/lambda_function.zip"
  excludes = [
    "__pycache__",
    "*.pyc",
    "*.pyo",
    "*.pyi",
    "*.dist-info",
    "*.egg-info",
    "tests",
    "test",
    "*.md",
    "*.txt",
    "*.rst",
    "*.html",
    "LICENSE*",
    "examples",
    "example",
    "samples",
    "docs",
    "doc",
    "*.so.*"
  ]
}

# S3 event notification to trigger Lambda for CSV and JSON files
resource "aws_s3_bucket_notification" "source_bucket_notification" {
  bucket = aws_s3_bucket.source.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_pipeline.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".csv"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_pipeline.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_pipeline.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source.arn
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# Lambda no longer needs S3 access - Glue handles all S3 operations

# IAM Policy for Lambda to write CloudWatch Logs
resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.project_name}-lambda-cloudwatch-policy-${var.environment}"
  role = aws_iam_role.lambda_role.id

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
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.etl_pipeline.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.etl_pipeline.arn
}

