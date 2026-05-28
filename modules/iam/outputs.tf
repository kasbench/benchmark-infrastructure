output "control_plane_instance_profile_name" {
  description = "Name of the control plane IAM instance profile"
  value       = aws_iam_instance_profile.control_plane.name
}

output "worker_instance_profile_name" {
  description = "Name of the worker node IAM instance profile"
  value       = aws_iam_instance_profile.worker_node.name
}

output "benchmark_runner_instance_profile_name" {
  description = "Name of the benchmark runner IAM instance profile"
  value       = aws_iam_instance_profile.benchmark_runner.name
}

output "all_roles" {
  description = "Map of all IAM roles and instance profiles for environment description"
  value = {
    control_plane    = { role_name = aws_iam_role.control_plane.name, profile_name = aws_iam_instance_profile.control_plane.name }
    worker_node      = { role_name = aws_iam_role.worker_node.name, profile_name = aws_iam_instance_profile.worker_node.name }
    benchmark_runner = { role_name = aws_iam_role.benchmark_runner.name, profile_name = aws_iam_instance_profile.benchmark_runner.name }
  }
}
