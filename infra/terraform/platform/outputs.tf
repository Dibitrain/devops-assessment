# The deploy job reads these to fill in the Helm values (see .github/workflows/deploy.yml).

output "aws_region" {
  value = var.aws_region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "app_namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.api.arn
}

output "alb_logs_bucket" {
  value = aws_s3_bucket.alb_logs.id
}

output "certificate_arn" {
  value = local.tls ? aws_acm_certificate_validation.api[0].certificate_arn : ""
}

output "api_hostname" {
  value = var.domain_name
}

output "api_key_secret_name" {
  description = "Secrets Manager secret holding the API key. Read it with: aws secretsmanager get-secret-value --secret-id <name>"
  value       = aws_secretsmanager_secret.api_key.name
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr_block
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
