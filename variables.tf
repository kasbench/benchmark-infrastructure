# =============================================================================
# Core Configuration
# =============================================================================

variable "environment_profile" {
  type        = string
  description = "Environment profile: small or benchmark"

  validation {
    condition     = contains(["small", "benchmark"], var.environment_profile)
    error_message = "environment_profile must be 'small' or 'benchmark'."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-1"
}

variable "availability_zone_mode" {
  type        = string
  description = "AZ selection mode: explicit or random"

  validation {
    condition     = contains(["explicit", "random"], var.availability_zone_mode)
    error_message = "availability_zone_mode must be 'explicit' or 'random'."
  }
}

variable "availability_zone" {
  type        = string
  description = "Explicit AZ (required when availability_zone_mode is 'explicit')"
  default     = null
}

variable "run_id" {
  type        = string
  description = "Unique identifier for this benchmark run"
}

variable "owner" {
  type        = string
  description = "Owner tag value for cost allocation"
}

# =============================================================================
# Network
# =============================================================================

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet"
  default     = "10.0.1.0/24"
}

# =============================================================================
# External Dependencies
# =============================================================================

variable "bastion_ssh_cidr" {
  type        = string
  description = "CIDR block for SSH access from the bastion host (e.g., \"172.31.23.100/32\")"
}

variable "bastion_vpc_id" {
  type        = string
  description = "VPC ID of the external bastion host (for VPC peering)"
  default     = ""
}

variable "bastion_vpc_cidr" {
  type        = string
  description = "CIDR block of the bastion VPC (for route table entries, e.g., \"172.31.0.0/16\")"
  default     = ""
}

variable "bastion_host_info" {
  type = object({
    instance_id = optional(string)
    private_ip  = optional(string)
    name        = optional(string)
  })
  description = "Bastion host reference information"
  default     = {}
}

variable "run_bucket_name" {
  type        = string
  description = "Name of the pre-existing S3 run bucket"
}

variable "artifact_prefixes" {
  type = object({
    environment = string
    reports     = string
    trials      = string
  })
  description = "S3 artifact prefix structure"
  default = {
    environment = "environment/"
    reports     = "reports/"
    trials      = "trials/"
  }
}

# =============================================================================
# AMIs
# =============================================================================

variable "ami_amd64" {
  type        = string
  description = "AMI ID for amd64 instances"
}

variable "ami_arm64" {
  type        = string
  description = "AMI ID for arm64 instances"
}

variable "ami_runner_amd64" {
  type        = string
  description = "AMI ID for amd64 runner instances"
}

# =============================================================================
# Compute
# =============================================================================

variable "spot" {
  type        = bool
  description = "Use spot instances for all EC2 instances (one-time request). Pass -var 'spot=true' to enable."
  default     = false
}

variable "benchmark_runner_config" {
  type = object({
    instance_type = string
  })
  description = "Benchmark runner instance configuration"
  default     = { instance_type = "t3.medium" }
}

variable "control_plane_config" {
  type = object({
    instance_type = string
  })
  description = "Control plane instance configuration"
  default     = { instance_type = "m8i.xlarge" }
}

variable "worker_groups" {
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
  description = "Worker node group configurations"
  default = {
    amd64 = { instance_type = "c8i.4xlarge", count = 5 }
    arm64 = { instance_type = "c8g.4xlarge", count = 5 }
  }

  validation {
    condition     = var.worker_groups.amd64.count >= 1 && var.worker_groups.arm64.count >= 1
    error_message = "Each worker group must have at least 1 node."
  }
}

variable "root_volume_config" {
  type = object({
    type       = string
    size_gib   = number
    iops       = optional(number)
    throughput = optional(number)
  })
  description = "Root EBS volume configuration for all EC2 instances"
  default = {
    type     = "gp3"
    size_gib = 100
  }
}

# =============================================================================
# Storage
# =============================================================================

variable "etcd_volume_config" {
  type = object({
    size_gib   = number
    type       = string
    iops       = optional(number)
    throughput = optional(number)
  })
  description = "EBS volume configuration for etcd"
  default = {
    size_gib   = 50
    type       = "gp3"
    iops       = 3000
    throughput = 125
  }
}

# =============================================================================
# Load Balancing
# =============================================================================

variable "nlb_config" {
  type = object({
    listeners = list(object({
      name                  = string
      listener_port         = number
      target_port           = number
      protocol              = string
      health_check_port     = number
      health_check_protocol = string
      health_check_path     = optional(string)
    }))
  })
  description = "NLB listener and target group configuration"
  default = {
    listeners = [{
      name                  = "http"
      listener_port         = 80
      target_port           = 30080
      protocol              = "TCP"
      health_check_port     = 30080
      health_check_protocol = "TCP"
      health_check_path     = null
    }]
  }
}

# =============================================================================
# Kubernetes Metadata (pass-through for environment description)
# =============================================================================

variable "kubernetes_metadata" {
  type = object({
    version           = optional(string)
    cni_plugin        = optional(string)
    cni_version       = optional(string)
    kube_proxy_mode   = optional(string)
    container_runtime = optional(string)
    helm_version      = optional(string)
  })
  description = "Kubernetes configuration metadata for environment description"
  default     = null
}

variable "observability_metadata" {
  type = object({
    prometheus_retention = optional(string)
    jaeger_retention     = optional(string)
    scrape_interval      = optional(string)
  })
  description = "Observability configuration metadata for environment description"
  default     = null
}

variable "autoscaler_metadata" {
  type = object({
    hpa_enabled           = optional(bool)
    vpa_enabled           = optional(bool)
    keda_enabled          = optional(bool)
    autoscaler_under_test = optional(string)
  })
  description = "Autoscaler configuration metadata for environment description"
  default     = null
}

# =============================================================================
# Operational
# =============================================================================

variable "debug_retention_enabled" {
  type        = bool
  description = "Prevent destruction of EC2/EBS in small profile for debugging"
  default     = false
}

variable "artifact_output_path" {
  type        = string
  description = "Local path for generated environment description files"
  default     = null
}

variable "trial_id" {
  type        = string
  description = "Optional trial ID for tagging"
  default     = null
}

# =============================================================================
# Locals
# =============================================================================

locals {
  common_tags = {
    Project            = "KASBench"
    EnvironmentProfile = var.environment_profile
    RunId              = var.run_id
    ManagedBy          = "OpenTofu"
    Owner              = var.owner
    Purpose            = "KubernetesAutoscalingBenchmark"
    TrialId            = var.trial_id != null ? var.trial_id : ""
  }

  artifact_output_path = var.artifact_output_path != null ? var.artifact_output_path : "artifacts/${var.run_id}/"
}
