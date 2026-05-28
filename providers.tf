provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project            = "KASBench"
      EnvironmentProfile = var.environment_profile
      RunId              = var.run_id
      ManagedBy          = "OpenTofu"
      Owner              = var.owner
      Purpose            = "KubernetesAutoscalingBenchmark"
    }
  }
}
