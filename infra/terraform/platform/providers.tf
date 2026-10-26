provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = var.name
      ManagedBy  = "terraform"
      Stack      = "platform"
      Repository = var.github_repository
    }
  }
}

# The Kubernetes and Helm providers authenticate with a short-lived token from `aws eks get-token`
# (the AWS CLI must be on PATH). Nothing long-lived is written to a kubeconfig.
locals {
  cluster_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = local.cluster_exec.api_version
    command     = local.cluster_exec.command
    args        = local.cluster_exec.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec                   = local.cluster_exec
  }
}
