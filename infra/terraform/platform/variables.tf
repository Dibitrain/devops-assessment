variable "aws_region" {
  description = "AWS region. eu-west-1 is the closest long-established region to Lagos with every service used here."
  type        = string
  default     = "eu-west-1"
}

variable "name" {
  description = "Name of the cluster, ECR repository and prefix for every resource. Must match `project` in bootstrap."
  type        = string
  default     = "accounts-api"
}

variable "github_repository" {
  description = "owner/name of the GitHub repository (used for tagging)."
  type        = string
  default     = ""
}

# ---- Network -------------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR. /16 leaves room for pod IPs (VPC CNI gives every pod a VPC address)."
  type        = string
  default     = "10.40.0.0/16"
}

variable "az_count" {
  description = "Availability zones to spread subnets and nodes across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2
    error_message = "At least two AZs are required for high availability."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, single-AZ egress) instead of one per AZ (HA)."
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = "Private VPC endpoints for ECR, STS, CloudWatch Logs and EC2 so node traffic to AWS stays off the NAT. About $0.01/hour per endpoint per AZ."
  type        = bool
  default     = true
}

# ---- Cluster -------------------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "EKS version. Keep it in standard support (`aws eks describe-cluster-versions`); extended support costs 6x more per hour."
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. GitHub-hosted runners have no fixed IPs, so this defaults to anywhere (still authenticated by IAM). Narrow it when using self-hosted runners."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "admin_principal_arns" {
  description = "Extra IAM role/user ARNs given cluster-admin (for example your SSO admin role) so humans can use kubectl."
  type        = list(string)
  default     = []
}

variable "github_role_names" {
  description = "Names of the CI roles created by the bootstrap stack."
  type = object({
    apply  = string
    deploy = string
  })
  default = {
    apply  = "github-accounts-api-apply"
    deploy = "github-accounts-api-deploy"
  }
}

# ---- Application edge ----------------------------------------------------------------------------

variable "app_namespace" {
  description = "Namespace the application is deployed into."
  type        = string
  default     = "accounts-api"
}

variable "domain_name" {
  description = "Public hostname for the API, e.g. api.example.com. Empty = no TLS certificate or DNS; the ALB serves plain HTTP on its AWS hostname (demo only)."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone that contains domain_name. Required when domain_name is set."
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "Requests allowed per client IP in any 5-minute window before WAF blocks it."
  type        = number
  default     = 1000
}

variable "api_key_version" {
  description = "Increment to rotate the API key: Terraform writes a fresh random value to Secrets Manager and External Secrets syncs it into the cluster."
  type        = number
  default     = 1
}

# ---- Operations ----------------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Retention for CloudWatch log groups (EKS control plane, VPC flow logs, WAF)."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Let `terraform destroy` delete non-empty ECR repositories and log buckets. True for demos, false for real environments."
  type        = bool
  default     = false
}
