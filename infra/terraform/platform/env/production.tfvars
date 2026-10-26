# Production profile: NAT gateway per AZ, private endpoints, three nodes, retained logs.
github_repository          = "femialaye/devops-assessment"
single_nat_gateway         = false
enable_interface_endpoints = true
node_min_size              = 3
node_desired_size          = 3
node_max_size              = 6
force_destroy              = false
log_retention_days         = 365

domain_name    = "api.example.com"
hosted_zone_id = "Z0000000000000000000"
