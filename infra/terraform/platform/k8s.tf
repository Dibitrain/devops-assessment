# In-cluster resources Terraform owns: the app namespace and the CI deployer's RBAC, plus the
# Grafana dashboard. The application itself is deployed by CI with Helm (deploy/helm/accounts-api).

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      # Pod Security Admission: reject any pod that is not non-root, capability-free and seccomp-confined.
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      # AWS LB Controller readiness gate: a new pod only counts as Ready once the ALB target group
      # reports it healthy, so a rolling update never removes old pods before new ones take traffic.
      "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled"
    }
  }

  depends_on = [module.eks]
}

# The deploy role maps to this group (eks.tf access entry). It can manage the app's resources in its
# own namespace and nothing else: no cluster-scoped resources, no other namespaces, no RBAC changes.
resource "kubernetes_role_v1" "deployer" {
  metadata {
    name      = "deployer"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "services", "serviceaccounts", "secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "events", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["servicemonitors", "prometheusrules"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["externalsecrets", "secretstores"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["elbv2.k8s.aws"]
    resources  = ["targetgroupbindings"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "deployer" {
  metadata {
    name      = "deployer"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = local.deployer_group
    api_group = "rbac.authorization.k8s.io"
  }
}

# Request rate / error rate / latency dashboard, committed as JSON and loaded by Grafana's sidecar.
resource "kubernetes_config_map_v1" "dashboard" {
  metadata {
    name      = "${var.name}-dashboard"
    namespace = "monitoring"
    labels    = { grafana_dashboard = "1" }
  }
  data = {
    "accounts-api.json" = file("${path.module}/../../../observability/dashboards/accounts-api.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
