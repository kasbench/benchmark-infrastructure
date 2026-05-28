terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "opentofu/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
