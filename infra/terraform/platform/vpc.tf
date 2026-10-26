# Three-tier-ready VPC across var.az_count AZs:
#   public  /24s - only the internet-facing ALB and NAT gateways live here
#   private /20s - EKS nodes and pods (VPC CNI gives each pod a VPC IP, hence the large subnets)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet discovery for the AWS Load Balancer Controller.
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }

  # The default security group allows all traffic between its members; strip every rule from it.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # VPC flow logs: network-level audit trail (ISO 27001 A.8.15/A.8.16, PCI DSS 10).
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = var.log_retention_days
  vpc_flow_log_iam_role_name                      = "${var.name}-vpc-flow-log"
  vpc_flow_log_iam_policy_name                    = "${var.name}-vpc-flow-log"
}

# Private connectivity to AWS APIs. The S3 gateway endpoint is free and carries ECR image layers;
# the interface endpoints keep ECR, STS, logs and EC2 API calls off the NAT gateways.
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.7"

  vpc_id = module.vpc.vpc_id

  create_security_group      = var.enable_interface_endpoints
  security_group_name_prefix = "${var.name}-vpce-"
  security_group_description = "HTTPS from inside the VPC to interface endpoints"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from the VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = merge(
    {
      s3 = {
        service         = "s3"
        service_type    = "Gateway"
        route_table_ids = module.vpc.private_route_table_ids
        tags            = { Name = "${var.name}-s3" }
      }
    },
    var.enable_interface_endpoints ? {
      for svc in ["ecr.api", "ecr.dkr", "sts", "logs", "ec2"] : replace(svc, ".", "_") => {
        service             = svc
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        tags                = { Name = "${var.name}-${svc}" }
      }
    } : {}
  )
}
