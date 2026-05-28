# =============================================================================
# Compute Module Outputs
# =============================================================================

output "control_plane_metadata" {
  value = {
    instance_id    = aws_instance.control_plane.id
    private_ip     = aws_instance.control_plane.private_ip
    instance_type  = aws_instance.control_plane.instance_type
    ami_id         = aws_instance.control_plane.ami
    architecture   = "amd64"
    subnet_id      = aws_instance.control_plane.subnet_id
    root_volume_id = aws_instance.control_plane.root_block_device[0].volume_id
  }
  description = "Control plane instance metadata for bootstrap handoff"
}

output "worker_nodes_metadata" {
  value = {
    amd64 = [for i, instance in aws_instance.worker_amd64 : {
      instance_id    = instance.id
      private_ip     = instance.private_ip
      instance_type  = instance.instance_type
      ami_id         = instance.ami
      architecture   = "amd64"
      subnet_id      = instance.subnet_id
      node_group     = "amd64"
      node_index     = i
      root_volume_id = instance.root_block_device[0].volume_id
    }]
    arm64 = [for i, instance in aws_instance.worker_arm64 : {
      instance_id    = instance.id
      private_ip     = instance.private_ip
      instance_type  = instance.instance_type
      ami_id         = instance.ami
      architecture   = "arm64"
      subnet_id      = instance.subnet_id
      node_group     = "arm64"
      node_index     = i
      root_volume_id = instance.root_block_device[0].volume_id
    }]
  }
  description = "Worker node metadata grouped by architecture for bootstrap handoff"
}

output "benchmark_runner_metadata" {
  value = {
    instance_id    = aws_instance.benchmark_runner.id
    public_ip      = aws_instance.benchmark_runner.public_ip
    private_ip     = aws_instance.benchmark_runner.private_ip
    instance_type  = aws_instance.benchmark_runner.instance_type
    ami_id         = aws_instance.benchmark_runner.ami
    architecture   = "amd64"
    subnet_id      = aws_instance.benchmark_runner.subnet_id
    root_volume_id = aws_instance.benchmark_runner.root_block_device[0].volume_id
  }
  description = "Benchmark runner instance metadata"
}
