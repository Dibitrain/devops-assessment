# Cost-reduced profile for the assessment: same architecture, cheaper redundancy.
# Roughly $0.45/hour while running (EKS control plane, 2 x t3.large, 1 NAT gateway, ALB, WAF).
github_repository          = "femialaye/devops-assessment"
single_nat_gateway         = true
enable_interface_endpoints = false
node_desired_size          = 2
node_max_size              = 3
force_destroy              = true
log_retention_days         = 30

# Optional TLS + DNS. Leave empty to serve plain HTTP on the ALB's AWS hostname.
domain_name    = ""
hosted_zone_id = ""
