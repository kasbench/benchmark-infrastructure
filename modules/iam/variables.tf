variable "run_bucket_name" {
  description = "Name of the pre-existing S3 run bucket for benchmark artifacts"
  type        = string
}

variable "environment_profile" {
  description = "Environment profile name (small or benchmark)"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all IAM resources"
  type        = map(string)
  default     = {}
}
