# Cluster add-ons installed with Helm. Each add-on that calls AWS gets its own IAM role through EKS
# Pod Identity, scoped to exactly the resources it needs (no node-role permissions are widened).

locals {
  chart_versions = {
    aws_load_balancer_controller = "3.6.2"
    external_secrets             = "2.14.0"
    metrics_server               = "3.14.0"
    kube_prometheus_stack        = "92.13.1"
    external_dns                 = "1.23.0"
  }
}

# ---- CloudWatch Observability add-on (installed in eks.tf): container and node logs -----------------

module "cloudwatch_observability_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name               = "${var.name}-cloudwatch"
  policy_name_prefix = "${var.name}-"

  attach_aws_cloudwatch_observability_policy = true
  # The association is created by the EKS add-on itself (eks.tf), so none here.
}

# Pre-create the add-on's log groups so they get a retention period (the agent would create them with
# "never expire").
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each          = toset(["application", "dataplane", "host", "performance"])
  name              = "/aws/containerinsights/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# ---- AWS Load Balancer Controller: turns the app's Ingress into an ALB --------------------------------

module "lbc_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name = "${var.name}-aws-lbc"
  # IAM names must stay under the "${var.name}-" prefix the CI apply role is allowed to manage.
  policy_name_prefix = "${var.name}-"

  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = local.chart_versions.aws_load_balancer_controller

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    # Pods cannot reach IMDS (hop limit 1), so region and VPC are passed explicitly.
    region = var.aws_region
    vpcId  = module.vpc.vpc_id
    serviceAccount = {
      name = "aws-load-balancer-controller"
    }
    replicaCount        = 2
    podDisruptionBudget = { maxUnavailable = 1 }
    # Only manage what we ask for: do not take over every Service of type LoadBalancer.
    enableServiceMutatorWebhook = false
  })]

  depends_on = [module.eks, module.lbc_pod_identity]
}

# ---- metrics-server: CPU/memory metrics for the HorizontalPodAutoscaler ------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = local.chart_versions.metrics_server

  values = [yamlencode({
    replicas            = 2
    podDisruptionBudget = { enabled = true, maxUnavailable = 1 }
  })]

  depends_on = [module.eks]
}

# ---- External Secrets Operator: syncs AWS Secrets Manager -> Kubernetes Secrets ----------------------

module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name = "${var.name}-external-secrets"
  # IAM names must stay under the "${var.name}-" prefix the CI apply role is allowed to manage.
  policy_name_prefix = "${var.name}-"

  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = [aws_secretsmanager_secret.api_key.arn]
  external_secrets_kms_key_arns         = [aws_kms_key.app.arn]
  external_secrets_create_permission    = false

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = local.chart_versions.external_secrets

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      name = "external-secrets"
    }
  })]

  depends_on = [module.eks, module.external_secrets_pod_identity]
}

# ---- Prometheus, Alertmanager and Grafana ------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = local.chart_versions.kube_prometheus_stack
  timeout          = 900

  values = [file("${path.module}/../../../observability/kube-prometheus-stack-values.yaml")]

  depends_on = [module.eks]
}

# ---- ExternalDNS: publishes the Ingress hostname to Route 53 (only with a domain) -------------------

module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"
  count   = local.tls ? 1 : 0

  name = "${var.name}-external-dns"
  # IAM names must stay under the "${var.name}-" prefix the CI apply role is allowed to manage.
  policy_name_prefix = "${var.name}-"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:${local.partition}:route53:::hostedzone/${var.hosted_zone_id}"]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }
}

resource "helm_release" "external_dns" {
  count      = local.tls ? 1 : 0
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = local.chart_versions.external_dns

  values = [yamlencode({
    provider      = { name = "aws" }
    sources       = ["ingress"]
    domainFilters = [var.domain_name]
    policy        = "sync"
    txtOwnerId    = var.name
    serviceAccount = {
      name = "external-dns"
    }
    env = [{ name = "AWS_DEFAULT_REGION", value = var.aws_region }]
  })]

  depends_on = [module.eks, module.external_dns_pod_identity]
}
