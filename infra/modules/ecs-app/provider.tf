terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.21"
    }
  }
  required_version = ">= 1.5.0, < 1.8.0"
}