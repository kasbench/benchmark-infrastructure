variable "vpc_id" {
  description = "ID of the VPC where security groups will be created"
  type        = string
}

variable "bastion_ssh_cidr" {
  description = "CIDR block for SSH access from the bastion host (e.g., \"10.0.1.10/32\")"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
