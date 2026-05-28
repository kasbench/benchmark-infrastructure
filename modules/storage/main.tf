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
    precondition {
      condition     = !(local.apply_debug_retention) || !tobool("false")
      error_message = "Debug retention is enabled for small profile. Disable debug_retention_enabled before destroying."
    }
  }
}
