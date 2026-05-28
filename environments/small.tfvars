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

run_id = "PLACEHOLDER-RUN-ID"  # Replace with actual run identifier
owner  = "PLACEHOLDER-OWNER"   # Replace with owner name for cost allocation

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"

# -----------------------------------------------------------------------------
# External Dependencies (PLACEHOLDERS - replace before apply)
# -----------------------------------------------------------------------------

bastion_security_group_id = "sg-PLACEHOLDER"          # Replace with bastion host SG ID
run_bucket_name           = "PLACEHOLDER-BUCKET-NAME" # Replace with pre-existing S3 bucket name

# -----------------------------------------------------------------------------
# AMIs (PLACEHOLDERS - replace before apply)
# -----------------------------------------------------------------------------

ami_amd64 = "ami-PLACEHOLDER-AMD64" # Replace with amd64 AMI ID
ami_arm64 = "ami-PLACEHOLDER-ARM64" # Replace with arm64 AMI ID

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------

control_plane_config = {
  instance_type = "t3.large"
}

benchmark_runner_config = {
  instance_type = "t3.medium"
}

worker_groups = {
  amd64 = {
    instance_type = "t3.large"
    count         = 1
  }
  arm64 = {
    instance_type = "t4g.large"
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
