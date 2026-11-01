terraform {
  # Require a modern Terraform release.
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

# Configure the AWS provider using the selected region.
provider "aws" {
  region = var.aws_region
}
