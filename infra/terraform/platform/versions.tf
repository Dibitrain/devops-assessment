terraform {
  # 1.11+: write-only attributes keep the API key out of state.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Partial configuration: the bucket name contains the account ID, so it is supplied at init time:
  #   terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<region>"
  # use_lockfile = S3-native locking (no DynamoDB table needed since Terraform 1.10).
  backend "s3" {
    key          = "platform/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
