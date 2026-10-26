terraform {
  # 1.10+ for S3-native state locking in the platform stack; 1.11+ for write-only attributes.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # Bootstrap creates the remote-state bucket, so it starts on local state. After the first apply you
  # can migrate it into the bucket it created: uncomment, then `terraform init -migrate-state`.
  # backend "s3" {
  #   key          = "bootstrap/terraform.tfstate"
  #   use_lockfile = true
  #   encrypt      = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = var.project
      ManagedBy  = "terraform"
      Stack      = "bootstrap"
      Repository = var.github_repository
    }
  }
}
