# Lambda Layer for heavy dependencies (pandas, numpy, pyarrow)
resource "null_resource" "package_lambda_layer" {
  triggers = {
    requirements = filemd5("${path.module}/../requirements.txt")
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
      $ErrorActionPreference = "Stop"
      $projectRoot = Resolve-Path (Join-Path "${path.module}" "..")
      Push-Location $projectRoot
      
      try {
        $scriptPath = Join-Path $projectRoot "scripts\package_lambda_layer.ps1"
        if (Test-Path $scriptPath) {
          & $scriptPath
        } else {
          Write-Host "Layer packaging script not found, creating layer manually..."
          $layerPath = Join-Path $projectRoot "lambda_layer\python"
          if (-not (Test-Path $layerPath)) {
            New-Item -ItemType Directory -Path $layerPath -Force | Out-Null
          }
          pip install pandas numpy pyarrow -t $layerPath --upgrade
        }
      } finally {
        Pop-Location
      }
    EOT
  }
}

# Create Lambda Layer zip
data "archive_file" "lambda_layer_zip" {
  depends_on = [null_resource.package_lambda_layer]
  type        = "zip"
  source_dir  = "${path.module}/../lambda_layer"
  output_path = "${path.module}/lambda_layer.zip"
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
    "doc"
  ]
}

# Lambda Layer resource
resource "aws_lambda_layer_version" "etl_dependencies" {
  layer_name          = "${var.project_name}-dependencies-${var.environment}"
  filename            = data.archive_file.lambda_layer_zip.output_path
  source_code_hash    = data.archive_file.lambda_layer_zip.output_base64sha256
  compatible_runtimes = ["python3.9", "python3.10", "python3.11", "python3.12"]

  description = "Heavy dependencies (pandas, numpy, pyarrow) for ETL pipeline"
}

# Lambda function for ETL pipeline triggered by S3 events
resource "aws_lambda_function" "etl_pipeline" {
  function_name = "${var.project_name}-etl-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.9"
  timeout       = 900  # 15 minutes max
  memory_size   = 3008  # Maximum memory for better performance

  # Package the Lambda function (code only, no heavy deps)
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Attach Lambda Layer with heavy dependencies
  layers = [aws_lambda_layer_version.etl_dependencies.arn]

  # Ensure CloudWatch log group exists before Lambda function
  depends_on = [aws_cloudwatch_log_group.etl_pipeline]

  environment {
    variables = {
      DESTINATION_BUCKET = aws_s3_bucket.destination.id
      OUTPUT_PREFIX      = "processed_data"
      CLOUDWATCH_LOG_GROUP = var.enable_cloudwatch ? aws_cloudwatch_log_group.etl_pipeline[0].name : "/aws/lambda/${var.project_name}-etl-${var.environment}"
      CLOUDWATCH_ENABLED   = tostring(var.enable_cloudwatch)
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
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
      $ErrorActionPreference = "Stop"
      # Change to project root directory
      $projectRoot = Resolve-Path (Join-Path "${path.module}" "..")
      Push-Location $projectRoot
      
      try {
        $scriptPath = Join-Path $projectRoot "scripts\package_lambda.ps1"
        if (Test-Path $scriptPath) {
          & $scriptPath
        } else {
          # Fallback: Create package directory manually
          $lambdaPackagePath = Join-Path $projectRoot "lambda_package"
          if (-not (Test-Path $lambdaPackagePath)) {
            New-Item -ItemType Directory -Path $lambdaPackagePath -Force | Out-Null
          }
          
          $files = @("etl_pipeline.py", "lambda_handler.py", "config.py")
          foreach ($file in $files) {
            $sourceFile = Join-Path $projectRoot $file
            if (Test-Path $sourceFile) {
              Copy-Item $sourceFile -Destination $lambdaPackagePath -Force
              Write-Host "Copied $file to lambda_package"
            }
          }
          
          Write-Host "Lambda package directory created at $lambdaPackagePath"
        }
      } finally {
        Pop-Location
      }
    EOT
  }
}

# Create deployment package
data "archive_file" "lambda_zip" {
  depends_on = [null_resource.package_lambda]
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

