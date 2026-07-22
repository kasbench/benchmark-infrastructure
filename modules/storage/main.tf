# Storage Module - Pre-created EBS volumes and StorageClass metadata
# Creates dedicated GP3 EBS volumes for etcd and outputs metadata for
# Kubernetes StorageClass configuration by the bootstrap process.

locals {
  apply_debug_retention = var.debug_retention_enabled && var.environment_profile == "small"
}

# =============================================================================
# Pre-Created EBS Volume for etcd
# =============================================================================

resource "aws_ebs_volume" "etcd" {
  availability_zone = var.availability_zone
  size              = var.etcd_volume_config.size_gib
  type              = var.etcd_volume_config.type
  iops              = var.etcd_volume_config.iops
  throughput        = var.etcd_volume_config.throughput
  encrypted         = true

  tags = merge(var.tags, {
    Name     = "kasbench-etcd"
    Workload = "etcd"
  })

  lifecycle {
    # Debug retention: block destroy when enabled for small profile.
    # Benchmark profile always permits destruction regardless of the flag.
    prevent_destroy = false

    precondition {
      condition     = !local.apply_debug_retention
      error_message = "Debug retention is enabled for the small profile. Set debug_retention_enabled=false before destroying EBS volumes."
    }
  }
}

# =============================================================================
# Amazon EFS File System - Execution Data
# =============================================================================
# One Zone storage in the same AZ as compute, no backups, no lifecycle,
# no encryption, enhanced throughput mode, general purpose performance.

resource "aws_efs_file_system" "execution_data" {
  creation_token = "kasbench-execution-data"

  availability_zone_name = var.availability_zone
  encrypted              = false
  throughput_mode        = "elastic"
  performance_mode       = "generalPurpose"

  protection {
    replication_overwrite = "ENABLED"
  }

  tags = merge(var.tags, {
    Name     = "execution-data"
    Workload = "execution-data"
  })
}

resource "aws_efs_backup_policy" "execution_data" {
  file_system_id = aws_efs_file_system.execution_data.id

  backup_policy {
    status = "DISABLED"
  }
}

resource "aws_efs_mount_target" "execution_data" {
  file_system_id  = aws_efs_file_system.execution_data.id
  subnet_id       = var.private_subnet_id
  security_groups = [var.efs_sg_id]
}
