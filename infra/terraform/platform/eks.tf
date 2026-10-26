module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # API server: reachable privately from the VPC, and publicly (IAM-authenticated) for CI and kubectl.
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Kubernetes Secrets are envelope-encrypted with a customer-managed KMS key (module default),
  # and every control-plane log type, including the Kubernetes audit log, goes to CloudWatch.
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # Workloads get AWS permissions through EKS Pod Identity (addons.tf), so no IRSA OIDC provider.
  enable_irsa = false

  # Access is granted explicitly below rather than to "whoever ran apply first".
  enable_cluster_creator_admin_permissions = false
  authentication_mode                      = "API"

  access_entries = merge(
    {
      github_apply = {
        principal_arn = data.aws_iam_role.github_apply.arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
      # Deploy role: no access policy, only a Kubernetes group bound to a namespace-scoped Role (k8s.tf).
      github_deploy = {
        principal_arn     = data.aws_iam_role.github_deploy.arn
        kubernetes_groups = [local.deployer_group]
      }
    },
    {
      for i, arn in var.admin_principal_arns : "admin_${i}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    }
  )

  addons = {
    # before_compute: CNI and Pod Identity agent must exist before nodes join.
    vpc-cni = {
      before_compute = true
      most_recent    = true
      # Enforce Kubernetes NetworkPolicy natively in the VPC CNI (used by the app chart).
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    # Fluent Bit + CloudWatch agent: ships every container's stdout (the app's JSON access logs) and node
    # logs to CloudWatch Logs, and collects Container Insights metrics.
    amazon-cloudwatch-observability = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = module.cloudwatch_observability_pod_identity.iam_role_arn
        service_account = "cloudwatch-agent"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      name            = "${var.name}-default"
      use_name_prefix = true
      iam_role_name   = "${var.name}-node"

      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Node upgrades and AMI rollouts replace at most a third of the nodes at a time; with PDBs on
      # every workload this keeps capacity and availability during upgrades.
      update_config = {
        max_unavailable_percentage = 33
      }

      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # IMDSv2 only, and hop limit 1 so pods cannot reach node credentials through the metadata service.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
}
