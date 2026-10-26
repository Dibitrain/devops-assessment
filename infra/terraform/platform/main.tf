data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Created by the bootstrap stack.
data "aws_iam_role" "github_apply" {
  name = var.github_role_names.apply
}

data "aws_iam_role" "github_deploy" {
  name = var.github_role_names.deploy
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  tls        = var.domain_name != ""

  # Kubernetes RBAC group the deploy role is mapped to (see k8s.tf).
  deployer_group = "${var.name}-deployers"
}

check "domain_requires_zone" {
  assert {
    condition     = !local.tls || var.hosted_zone_id != ""
    error_message = "hosted_zone_id must be set when domain_name is set."
  }
}
