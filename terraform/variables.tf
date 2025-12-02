variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "etl-pipeline"
}

variable "source_bucket_name" {
  description = "Name of the source S3 bucket"
  type        = string
  default     = ""
}

variable "destination_bucket_name" {
  description = "Name of the destination S3 bucket"
  type        = string
  default     = ""
}

variable "enable_cloudwatch" {
  description = "Enable CloudWatch logging"
  type        = bool
  default     = true
}

variable "enable_ec2" {
  description = "Enable EC2 instance for ETL processing"
  type        = bool
  default     = false
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

