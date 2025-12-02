# IAM Role for ETL Pipeline (for EC2 or Lambda)
resource "aws_iam_role" "etl_pipeline_role" {
  name = "${var.project_name}-etl-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = var.enable_ec2 ? "ec2.amazonaws.com" : "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-etl-role"
  }
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "etl_s3_policy" {
  name = "${var.project_name}-s3-policy-${var.environment}"
  role = aws_iam_role.etl_pipeline_role.id

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

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "etl_cloudwatch_policy" {
  name = "${var.project_name}-cloudwatch-policy-${var.environment}"
  role = aws_iam_role.etl_pipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:${var.project_name}-*"
      }
    ]
  })
}

# Instance Profile for EC2 (if enabled)
resource "aws_iam_instance_profile" "etl_instance_profile" {
  count = var.enable_ec2 ? 1 : 0
  name  = "${var.project_name}-instance-profile-${var.environment}"
  role  = aws_iam_role.etl_pipeline_role.name
}

output "etl_role_arn" {
  description = "ARN of the ETL pipeline IAM role"
  value       = aws_iam_role.etl_pipeline_role.arn
}

output "etl_role_name" {
  description = "Name of the ETL pipeline IAM role"
  value       = aws_iam_role.etl_pipeline_role.name
}

