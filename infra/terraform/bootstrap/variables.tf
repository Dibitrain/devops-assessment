variable "aws_region" {
  description = "Region for the state bucket and the platform."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Name prefix. Must match `name` in the platform stack: the CI apply role may only manage IAM resources that start with it."
  type        = string
  default     = "accounts-api"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name."
  type        = string
}

variable "github_environment" {
  description = "GitHub environment whose jobs may assume the apply and deploy roles. Protect it with required reviewers and a main-only branch rule."
  type        = string
  default     = "production"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set false if the account already has one (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "create_cloudtrail" {
  description = "Create a multi-region CloudTrail trail. Set false if the account or organization already has one."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Days to keep CloudTrail logs in S3 before expiry."
  type        = number
  default     = 365
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete non-empty log and state buckets. Keep false outside of throwaway demos."
  type        = bool
  default     = false
}
