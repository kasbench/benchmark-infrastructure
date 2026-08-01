# =============================================================================
# Benchmark Runner Instance
# =============================================================================

resource "aws_instance" "benchmark_runner" {
  ami                         = var.ami_runner_amd64
  instance_type               = var.benchmark_runner_config.instance_type
  subnet_id                   = var.public_subnet_id
  availability_zone           = var.availability_zone
  vpc_security_group_ids      = [var.benchmark_runner_sg_id]
  iam_instance_profile        = var.benchmark_runner_profile_name
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = local.cloud_init_script

  dynamic "instance_market_options" {
    for_each = var.spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type = "one-time"
      }
    }
  }

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name              = "kasbench-benchmark-runner"
    "kubernetes-role" = "benchmark-runner"
    "kubernetes-arch" = "amd64"
  })
}
