# Lambda function for ETL pipeline triggered by S3 events
resource "aws_lambda_function" "etl_pipeline" {
  function_name = "${var.project_name}-etl-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.9"
  timeout       = 900  # 15 minutes max
  memory_size   = 3008  # Maximum memory for better performance

  # Package the Lambda function
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DESTINATION_BUCKET = aws_s3_bucket.destination.id
      AWS_REGION         = var.aws_region
      OUTPUT_PREFIX      = "processed_data"
      CLOUDWATCH_LOG_GROUP = "${var.project_name}-${var.environment}"
      CLOUDWATCH_ENABLED   = "true"
    }
  }

  tags = {
    Name = "${var.project_name}-etl-lambda"
  }
}

# Package Lambda function before deployment
resource "null_resource" "package_lambda" {
  triggers = {
    etl_pipeline = filemd5("${path.module}/../etl_pipeline.py")
    lambda_handler = filemd5("${path.module}/../lambda_handler.py")
    config = filemd5("${path.module}/../config.py")
    requirements = filemd5("${path.module}/../requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ -f "${path.module}/../scripts/package_lambda.sh" ]; then
        bash "${path.module}/../scripts/package_lambda.sh"
      else
        echo "Creating lambda_package directory..."
        mkdir -p "${path.module}/../lambda_package"
        cp "${path.module}/../etl_pipeline.py" "${path.module}/../lambda_package/"
        cp "${path.module}/../lambda_handler.py" "${path.module}/../lambda_package/"
        cp "${path.module}/../config.py" "${path.module}/../lambda_package/"
      fi
    EOT
  }
}

# Create deployment package
data "archive_file" "lambda_zip" {
  depends_on = [null_resource.package_lambda]
  type        = "zip"
  source_dir  = "${path.module}/../lambda_package"
  output_path = "${path.module}/lambda_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", "*.dist-info", "tests"]
}

# S3 event notification to trigger Lambda
resource "aws_s3_bucket_notification" "source_bucket_notification" {
  bucket = aws_s3_bucket.source.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_pipeline.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".csv"
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

# IAM Policy for Lambda to access S3
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.project_name}-lambda-s3-policy-${var.environment}"
  role = aws_iam_role.lambda_role.id

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
          "${aws_s3_bucket.destination.arn}/*"
        ]
      }
    ]
  })
}

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

# Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.etl_pipeline.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.etl_pipeline.arn
}

