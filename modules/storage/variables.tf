variable "availability_zone" {
  description = "Availability zone for EBS volumes (must match compute instances)"
  type        = string
}

variable "etcd_volume_config" {
  description = "EBS volume configuration for etcd"
  type = object({
    size_gib   = number
    type       = string
    iops       = optional(number)
    throughput = optional(number)
  })
}

variable "environment_profile" {
  description = "Environment profile name (small or benchmark)"
  type        = string
}

variable "debug_retention_enabled" {
  description = "Prevent destruction of EBS volumes in small profile for debugging"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags to apply to all storage resources"
  type        = map(string)
  default     = {}
}
