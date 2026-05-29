# =============================================================================
# Network
# =============================================================================

variable "public_subnet_id" {
  description = "ID of the public subnet for the benchmark-runner"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the private subnet for control plane and worker nodes"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for all compute instances"
  type        = string
}

# =============================================================================
# Instance Configurations
# =============================================================================

variable "benchmark_runner_config" {
  description = "Benchmark runner instance configuration"
  type = object({
    instance_type = string
  })
}

variable "control_plane_config" {
  description = "Control plane instance configuration"
  type = object({
    instance_type = string
  })
}

variable "worker_groups" {
  description = "Worker node group configurations by architecture"
  type = object({
    amd64 = object({
      instance_type = string
      count         = number
    })
    arm64 = object({
      instance_type = string
      count         = number
    })
  })
}

variable "root_volume_config" {
  description = "Root EBS volume configuration for all EC2 instances"
  type = object({
    type       = string
    size_gib   = number
    iops       = optional(number)
    throughput = optional(number)
  })
}

# =============================================================================
# AMIs
# =============================================================================

variable "ami_amd64" {
  description = "AMI ID for amd64 architecture instances"
  type        = string
}

variable "ami_arm64" {
  description = "AMI ID for arm64 architecture instances"
  type        = string
}

# =============================================================================
# SSH Key Pair
# =============================================================================

variable "key_name" {
  description = "EC2 key pair name to assign to all fleet instances"
  type        = string

  validation {
    condition     = length(var.key_name) > 0
    error_message = "A non-empty key pair name is required."
  }
}

variable "fleet_public_key" {
  description = "SSH public key (OpenSSH format) to inject into all fleet instances via cloud-init"
  type        = string
}

# =============================================================================
# Security Groups
# =============================================================================

variable "benchmark_runner_sg_id" {
  description = "Security group ID for the benchmark-runner instance"
  type        = string
}

variable "control_plane_sg_id" {
  description = "Security group ID for the control plane instance"
  type        = string
}

variable "worker_node_sg_id" {
  description = "Security group ID for worker node instances"
  type        = string
}

# =============================================================================
# IAM Instance Profiles
# =============================================================================

variable "control_plane_profile_name" {
  description = "IAM instance profile name for the control plane"
  type        = string
}

variable "worker_profile_name" {
  description = "IAM instance profile name for worker nodes"
  type        = string
}

variable "benchmark_runner_profile_name" {
  description = "IAM instance profile name for the benchmark-runner"
  type        = string
}

# =============================================================================
# Storage
# =============================================================================

variable "etcd_volume_id" {
  description = "ID of the pre-created EBS volume for etcd"
  type        = string
}

# =============================================================================
# Operational
# =============================================================================

variable "environment_profile" {
  description = "Environment profile name (small or benchmark)"
  type        = string
}

variable "debug_retention_enabled" {
  description = "Prevent destruction of EC2/EBS in small profile for debugging"
  type        = bool
  default     = false
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Common tags to apply to all compute resources"
  type        = map(string)
  default     = {}
}
