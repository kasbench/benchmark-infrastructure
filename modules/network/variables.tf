variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
}

variable "availability_zone_mode" {
  description = "AZ selection mode: 'explicit' to use a specified AZ, 'random' to select one randomly"
  type        = string

  validation {
    condition     = contains(["explicit", "random"], var.availability_zone_mode)
    error_message = "availability_zone_mode must be either 'explicit' or 'random'."
  }
}

variable "availability_zone" {
  description = "Explicit availability zone to use when availability_zone_mode is 'explicit'"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}
