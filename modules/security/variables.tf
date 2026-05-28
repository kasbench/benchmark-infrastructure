variable "vpc_id" {
  description = "ID of the VPC where security groups will be created"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Security group ID of the external bastion host for SSH access"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
