# GitHub Actions authenticates to AWS with short-lived OIDC tokens. No access keys are stored in GitHub.
#
# Three roles, each trusted by exactly one kind of workflow run:
#   plan   - pull requests: read-only, runs `terraform plan -refresh=false`
#   apply  - jobs in the protected GitHub environment: manages infrastructure
#   deploy - jobs in the protected GitHub environment: pushes one ECR repo, deploys into one namespace
#
# Role names deliberately do NOT start with var.project: the apply role may manage IAM resources named
# "${var.project}-*", and keeping its own role outside that prefix stops it from editing itself.

locals {
  oidc_host        = "token.actions.githubusercontent.com"
  oidc_provider    = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_host}"
  env_subject      = "repo:${var.github_repository}:environment:${var.github_environment}"
  pr_subject       = "repo:${var.github_repository}:pull_request"
  iam_prefix_arns  = ["role", "policy", "instance-profile"]
  ecr_repo_arn     = "arn:${local.partition}:ecr:${var.aws_region}:${local.account_id}:repository/${var.project}"
  eks_cluster_arn  = "arn:${local.partition}:eks:${var.aws_region}:${local.account_id}:cluster/${var.project}"
  state_object_arn = "${aws_s3_bucket.state.arn}/*"
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust" {
  for_each = {
    plan   = local.pr_subject
    apply  = local.env_subject
    deploy = local.env_subject
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [each.value]
    }
  }
}

# ---- plan: read-only ---------------------------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name                 = "github-${var.project}-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn, local.state_object_arn]
  }
  statement {
    sid       = "StateLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
  statement {
    sid       = "StateKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# ---- apply: infrastructure ---------------------------------------------------------------------------
# PowerUserAccess covers every service except IAM. IAM is granted only on resources named
# "${var.project}-*", and attaching the broadest AWS-managed policies is explicitly denied.

resource "aws_iam_role" "apply" {
  name                 = "github-${var.project}-apply"
  assume_role_policy   = data.aws_iam_policy_document.trust["apply"].json
  max_session_duration = 7200 # EKS create/upgrade can exceed an hour
}

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_iam" {
  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    sid       = "ManageProjectIam"
    actions   = ["iam:*"]
    resources = [for t in local.iam_prefix_arns : "arn:${local.partition}:iam::${local.account_id}:${t}/${var.project}-*"]
  }
  statement {
    sid    = "NoPrivilegeEscalationViaManagedPolicies"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:AttachUserPolicy",
      "iam:AttachGroupPolicy",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = [
        "arn:${local.partition}:iam::aws:policy/AdministratorAccess",
        "arn:${local.partition}:iam::aws:policy/IAMFullAccess",
        "arn:${local.partition}:iam::aws:policy/PowerUserAccess",
      ]
    }
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "project-scoped-iam"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}

# ---- deploy: push one image, deploy into one namespace ---------------------------------------------
# Kubernetes permissions come from an EKS access entry in the platform stack that maps this role to a
# namespace-scoped RBAC group. The role cannot touch Terraform state or any other AWS resource.

resource "aws_iam_role" "deploy" {
  name                 = "github-${var.project}-deploy"
  assume_role_policy   = data.aws_iam_policy_document.trust["deploy"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [local.ecr_repo_arn]
  }
  statement {
    sid       = "EksConnect"
    actions   = ["eks:DescribeCluster"]
    resources = [local.eks_cluster_arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "ecr-push-eks-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
