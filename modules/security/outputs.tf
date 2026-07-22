# =============================================================================
# Security Module Outputs
# =============================================================================

output "benchmark_runner_sg_id" {
  description = "Security group ID for the benchmark runner instance"
  value       = aws_security_group.benchmark_runner.id
}

output "nlb_sg_id" {
  description = "Security group ID for the internal NLB"
  value       = aws_security_group.nlb.id
}

output "control_plane_sg_id" {
  description = "Security group ID for the Kubernetes control plane"
  value       = aws_security_group.control_plane.id
}

output "worker_node_sg_id" {
  description = "Security group ID for the Kubernetes worker nodes"
  value       = aws_security_group.worker_node.id
}

output "efs_sg_id" {
  description = "Security group ID for EFS mount targets"
  value       = aws_security_group.efs.id
}

output "all_security_groups" {
  description = "All security groups with IDs, names, and rule descriptions"
  value = {
    benchmark_runner = {
      id    = aws_security_group.benchmark_runner.id
      name  = aws_security_group.benchmark_runner.name
      rules = "SSH from bastion only; all egress"
    }
    nlb = {
      id    = aws_security_group.nlb.id
      name  = aws_security_group.nlb.name
      rules = "TCP from benchmark-runner only"
    }
    control_plane = {
      id    = aws_security_group.control_plane.id
      name  = aws_security_group.control_plane.name
      rules = "6443 from workers/runner; 2379-2380 self; 10250 from workers; SSH from bastion"
    }
    worker_node = {
      id    = aws_security_group.worker_node.id
      name  = aws_security_group.worker_node.name
      rules = "10250 from CP; 30000-32767 self; 9090/9100 self; SSH from bastion; all egress"
    }
    efs = {
      id    = aws_security_group.efs.id
      name  = aws_security_group.efs.name
      rules = "NFS 2049 from worker nodes; all egress"
    }
  }
}
