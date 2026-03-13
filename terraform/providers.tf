terraform {
  required_version = ">= 1.0"


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}


provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile


  default_tags {
    tags = {
      Project     = "cloud-security-portfolio"
      ManagedBy   = "terraform"
      Environment = "lab"
    }
  }
}
