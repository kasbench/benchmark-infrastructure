variable "vpc_id" {
  description = "VPC ID for target group association"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for internet-facing NLB placement"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID (retained for future use)"
  type        = string
}

variable "nlb_sg_id" {
  description = "Security group ID for the internal NLB"
  type        = string
}

variable "nlb_config" {
  description = "NLB listener and target group configuration"
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
}

variable "tags" {
  description = "Common tags to apply to all load-balancing resources"
  type        = map(string)
  default     = {}
}

variable "worker_instance_ids" {
  description = "List of worker node instance IDs to register as NLB targets"
  type        = list(string)
}
