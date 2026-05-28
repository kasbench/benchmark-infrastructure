# =============================================================================
# Worker Node Groups
# =============================================================================

resource "aws_instance" "worker_amd64" {
  count = var.worker_groups.amd64.count

  ami                    = var.ami_amd64
  instance_type          = var.worker_groups.amd64.instance_type
  subnet_id              = var.private_subnet_id
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [var.worker_node_sg_id]
  iam_instance_profile   = var.worker_profile_name

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name              = "kasbench-worker-amd64-${count.index}"
    "kubernetes-role" = "worker"
    "kubernetes-arch" = "amd64"
    "node-group"      = "amd64"
    "node-index"      = tostring(count.index)
  })

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_instance" "worker_arm64" {
  count = var.worker_groups.arm64.count

  ami                    = var.ami_arm64
  instance_type          = var.worker_groups.arm64.instance_type
  subnet_id              = var.private_subnet_id
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [var.worker_node_sg_id]
  iam_instance_profile   = var.worker_profile_name

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name              = "kasbench-worker-arm64-${count.index}"
    "kubernetes-role" = "worker"
    "kubernetes-arch" = "arm64"
    "node-group"      = "arm64"
    "node-index"      = tostring(count.index)
  })

  lifecycle {
    prevent_destroy = false
  }
}
