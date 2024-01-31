terraform {
  backend "s3" {
    bucket         = "jmajaca-tf"
    dynamodb_table = "jmajaca-tf"
    encrypt        = true
    key            = "demo-api"
    region         = "eu-central-1"
    profile        = "personal"
  }
}