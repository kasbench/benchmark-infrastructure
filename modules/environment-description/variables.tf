# =============================================================================
# Environment Description Module - Input Variables
# =============================================================================

# =============================================================================
# Core Identifiers
# =============================================================================

variable "run_id" {
  type        = string
  description = "Unique identifier for this benchmark run"
}

variable "environment_profile" {
  type        = string
  description = "Environment profile name (small or benchmark)"
}

variable "aws_region" {
  type        = string
  description = "AWS region where infrastructure is deployed"
}

variable "availability_zone" {
  type        = string
  description = "Selected availability zone for the deployment"
}

variable "output_path" {
  type        = string
  description = "Local filesystem path for generated report files"
}

# =============================================================================
# Network Outputs
# =============================================================================

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet CIDR block"
}

variable "igw_id" {
  type        = string
  description = "Internet Gateway ID"
}

variable "route_table_ids" {
  type        = map(string)
  description = "Map of route table IDs (public, private)"
}

# =============================================================================
# Security Outputs
# =============================================================================

variable "security_groups" {
  type = map(object({
    id    = string
    name  = string
    rules = string
  }))
  description = "Map of security groups with id, name, and rule descriptions"
}

# =============================================================================
# IAM Outputs
# =============================================================================

variable "iam_roles" {
  type = map(object({
    role_name    = string
    profile_name = string
  }))
  description = "Map of IAM roles with role_name and profile_name"
}

# =============================================================================
# Compute Outputs
# =============================================================================

variable "control_plane_metadata" {
  type = object({
    instance_id    = string
    private_ip     = string
    instance_type  = string
    ami_id         = string
    architecture   = string
    subnet_id      = string
    root_volume_id = string
  })
  description = "Control plane instance metadata"
}

variable "worker_nodes_metadata" {
  type = object({
    amd64 = list(object({
      instance_id    = string
      private_ip     = string
      instance_type  = string
      ami_id         = string
      architecture   = string
      subnet_id      = string
      node_group     = string
      node_index     = number
      root_volume_id = string
    }))
    arm64 = list(object({
      instance_id    = string
      private_ip     = string
      instance_type  = string
      ami_id         = string
      architecture   = string
      subnet_id      = string
      node_group     = string
      node_index     = number
      root_volume_id = string
    }))
  })
  description = "Worker node metadata grouped by architecture"
}

variable "benchmark_runner_metadata" {
  type = object({
    instance_id    = string
    public_ip      = string
    private_ip     = string
    instance_type  = string
    ami_id         = string
    architecture   = string
    subnet_id      = string
    root_volume_id = string
  })
  description = "Benchmark runner instance metadata"
}

# =============================================================================
# Load Balancing Outputs
# =============================================================================

variable "nlb_metadata" {
  type = object({
    dns_name = string
    arn      = string
    scheme   = string
    listeners = map(object({
      port     = number
      protocol = string
    }))
    target_groups = map(object({
      arn  = string
      port = number
    }))
  })
  description = "Internal NLB metadata including DNS, listeners, and target groups"
}

# =============================================================================
# Storage Outputs
# =============================================================================

variable "ebs_volumes" {
  type = map(object({
    volume_id  = string
    size_gib   = number
    type       = string
    iops       = number
    throughput = number
    az         = string
    workload   = string
  }))
  description = "Map of pre-created EBS volumes with metadata"
}

variable "storage_class_metadata" {
  type        = any
  description = "StorageClass metadata for Kubernetes bootstrap (variable structure per class)"
}

# =============================================================================
# External References
# =============================================================================

variable "bastion_host_info" {
  type = object({
    instance_id = optional(string)
    private_ip  = optional(string)
    name        = optional(string)
  })
  description = "Bastion host reference information"
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
}

# =============================================================================
# Metadata (pass-through from root)
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
