terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.21"
    }
  }
  required_version = ">= 1.5.0, < 1.8.0"
}

provider "aws" {
  region  = "eu-central-1"
  profile = "personal"
  
  default_tags {
    tags = {
      ManagedBy = "Terraform"
    }
  }
}