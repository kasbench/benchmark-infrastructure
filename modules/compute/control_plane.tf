# =============================================================================
# Control Plane Instance
# =============================================================================

resource "aws_instance" "control_plane" {
  ami                    = var.ami_amd64
  instance_type          = var.control_plane_config.instance_type
  subnet_id              = var.private_subnet_id
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [var.control_plane_sg_id]
  iam_instance_profile   = var.control_plane_profile_name

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name              = "kasbench-control-plane"
    "kubernetes-role" = "control-plane"
    "kubernetes-arch" = "amd64"
  })

  lifecycle {
    prevent_destroy = false
    precondition {
      condition     = !(var.debug_retention_enabled && var.environment_profile == "benchmark")
      error_message = "debug_retention_enabled must not be true when environment_profile is 'benchmark'"
    }
  }
}

# =============================================================================
# Etcd EBS Volume Attachment
# =============================================================================

resource "aws_volume_attachment" "etcd" {
  device_name = "/dev/xvdf"
  volume_id   = var.etcd_volume_id
  instance_id = aws_instance.control_plane.id
}
