# =============================================================================
# KASBench Infrastructure - Root Module Outputs
# =============================================================================
# Exposes all information required by the Kubernetes bootstrap process and
# for reproducibility auditing.
#
# Requirements: 10.3, 18.3, 19.1, 19.2, 19.3, 19.4, 19.5, 19.6, 23.1, 23.2, 23.3
# =============================================================================

# =============================================================================
# Kubernetes Bootstrap Handoff Outputs
# =============================================================================

output "control_plane" {
  description = "Control plane instance metadata for Kubernetes bootstrap"
  value       = module.compute.control_plane_metadata
}

output "worker_nodes" {
  description = "Worker node metadata grouped by architecture for Kubernetes bootstrap"
  value       = module.compute.worker_nodes_metadata
}

output "benchmark_runner" {
  description = "Benchmark runner instance metadata"
  value       = module.compute.benchmark_runner_metadata
}

output "nlb" {
  description = "Internal NLB metadata including DNS name and target group ARNs"
  value       = module.load_balancing.nlb_metadata
}

output "security_groups" {
  description = "All security group IDs and rule descriptions"
  value       = module.security.all_security_groups
}

output "storage" {
  description = "Pre-created EBS volume IDs and StorageClass metadata"
  value = {
    ebs_volumes            = module.storage.all_volumes
    storage_class_metadata = module.storage.storage_class_metadata
  }
}

output "network" {
  description = "VPC ID, subnet IDs, and availability zone"
  value = {
    vpc_id                     = module.network.vpc_id
    public_subnet_id           = module.network.public_subnet_id
    private_subnet_id          = module.network.private_subnet_id
    selected_availability_zone = module.network.selected_availability_zone
    igw_id                     = module.network.igw_id
    nat_gw_id                  = module.network.nat_gw_id
    route_table_ids            = module.network.route_table_ids
  }
}

output "run_bucket_name" {
  description = "S3 run bucket name for artifact storage"
  value       = var.run_bucket_name
}

output "run_id" {
  description = "Unique identifier for this benchmark run"
  value       = var.run_id
}

output "environment_description_paths" {
  description = "Paths to generated JSON, Markdown, and checksums files"
  value = {
    json_path      = module.environment_description.json_path
    markdown_path  = module.environment_description.markdown_path
    checksums_path = module.environment_description.checksums_path
  }
}

# =============================================================================
# Reproducibility Auditing Outputs
# =============================================================================

output "ami_ids" {
  description = "AMI IDs used in this provisioning run for reproducibility auditing"
  value = {
    amd64 = var.ami_amd64
    arm64 = var.ami_arm64
  }
}

output "provisioning_metadata" {
  description = "OpenTofu version, creation timestamp, and git commit hash for reproducibility"
  value = {
    opentofu_version = ">=1.6.0 (constraint)"
    creation_timestamp = timestamp()
    git_commit_hash    = try(trimspace(file("${path.root}/.git/refs/heads/main")), try(trimspace(file("${path.root}/.git/HEAD")), "unknown"))
  }
}

# =============================================================================
# SSH Key Management Outputs
# =============================================================================

output "ssh_private_key_path" {
  description = "Local file path to the generated SSH private key"
  value       = local_sensitive_file.fleet_private_key.filename
  sensitive   = true
}

output "ssh_key_pair_name" {
  description = "AWS EC2 key pair name assigned to all fleet instances"
  value       = aws_key_pair.fleet_key.key_name
}

# =============================================================================
# Verification Output (Requirement 18.3)
# =============================================================================

output "environment_profile" {
  description = "Active environment profile for verification before teardown"
  value       = var.environment_profile
}
