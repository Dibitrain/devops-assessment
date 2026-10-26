output "state_bucket" {
  description = "Set as the TF_STATE_BUCKET GitHub repository variable."
  value       = aws_s3_bucket.state.id
}

output "plan_role_arn" {
  description = "Set as the AWS_PLAN_ROLE_ARN GitHub repository variable."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as the AWS_APPLY_ROLE_ARN GitHub repository variable."
  value       = aws_iam_role.apply.arn
}

output "deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN GitHub repository variable."
  value       = aws_iam_role.deploy.arn
}

output "github_variables" {
  description = "Copy-paste commands to configure the repository (requires the gh CLI)."
  value       = <<-EOT
    gh variable set AWS_REGION          --body "${var.aws_region}"
    gh variable set TF_STATE_BUCKET     --body "${aws_s3_bucket.state.id}"
    gh variable set AWS_PLAN_ROLE_ARN   --body "${aws_iam_role.plan.arn}"
    gh variable set AWS_APPLY_ROLE_ARN  --body "${aws_iam_role.apply.arn}"
    gh variable set AWS_DEPLOY_ROLE_ARN --body "${aws_iam_role.deploy.arn}"
  EOT
}
