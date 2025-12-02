terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
  
  backend "s3" {
    # Configure backend in backend.tf or use local backend for development
    # bucket = "your-terraform-state-bucket"
    # key    = "etl-pipeline/terraform.tfstate"
    # region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "ETL-Pipeline"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "random" {
  # Random provider for generating unique IDs
}

