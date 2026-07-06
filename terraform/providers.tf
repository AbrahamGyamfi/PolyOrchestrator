terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.53"
    }
  }

  # Uncomment to store state remotely (recommended for teams)
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "businessconnect/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Retrieve the currently-running caller identity (used for ECR policy)
data "aws_caller_identity" "current" {}

# Retrieve available AZs in the chosen region
data "aws_availability_zones" "available" {
  state = "available"
}
