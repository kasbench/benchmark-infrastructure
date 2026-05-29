# =============================================================================
# Control Plane Instance
# =============================================================================

locals {
  apply_debug_retention = var.debug_retention_enabled && var.environment_profile == "small"
}

resource "aws_instance" "control_plane" {
  ami                    = var.ami_amd64
  instance_type          = var.control_plane_config.instance_type
  subnet_id              = var.private_subnet_id
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [var.control_plane_sg_id]
  iam_instance_profile   = var.control_plane_profile_name
  key_name               = var.key_name
  user_data              = local.cloud_init_script

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

    # Debug retention: block destroy when enabled for small profile.
    # Benchmark profile always permits destruction regardless of the flag.
    precondition {
      condition     = !local.apply_debug_retention
      error_message = "Debug retention is enabled for the small profile. Set debug_retention_enabled=false before destroying EC2 instances."
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
