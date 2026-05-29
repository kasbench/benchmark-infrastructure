# =============================================================================
# KASBench Small Environment Profile
# =============================================================================
# Purpose: Lightweight development/iteration environment with minimal resources.
# Usage:   tofu apply -var-file=environments/small.tfvars
#
# This profile uses smaller instance types, single-node worker groups, and
# reduced volume sizes to minimize cost during development and testing.
# =============================================================================

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

environment_profile    = "small"
aws_region             = "us-east-1"
availability_zone_mode = "explicit"
availability_zone      = "us-east-1a"

run_id = "dissertation-0001"  # Replace with actual run identifier
owner  = "dissertation"   # Replace with owner name for cost allocation

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"

# -----------------------------------------------------------------------------
# External Dependencies (PLACEHOLDERS - replace before apply)
# -----------------------------------------------------------------------------

bastion_ssh_cidr           = "172.31.23.100/32"                # Bastion host private IP
bastion_vpc_id             = "vpc-66884d1b"                     # Bastion VPC ID (for peering)
bastion_vpc_cidr           = "172.31.0.0/16"                    # Bastion VPC CIDR (for routing)
run_bucket_name           = "kasbench-test-20260528-377288663341-us-east-1-an " # Replace with pre-existing S3 bucket name

# -----------------------------------------------------------------------------
# AMIs (PLACEHOLDERS - replace before apply)
# -----------------------------------------------------------------------------

ami_amd64 = "ami-0fe3aecf802a4a5ef" # Replace with amd64 AMI ID
ami_arm64 = "ami-0d51796052932dddc" # Replace with arm64 AMI ID

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------

control_plane_config = {
  instance_type = "t3.small"
}

benchmark_runner_config = {
  instance_type = "t3.small"
}

worker_groups = {
  amd64 = {
    instance_type = "t3.small"
    count         = 1
  }
  arm64 = {
    instance_type = "t4g.small"
    count         = 1
  }
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------

root_volume_config = {
  type     = "gp3"
  size_gib = 50
}

etcd_volume_config = {
  size_gib   = 20
  type       = "gp3"
  iops       = 3000
  throughput = 125
}
