# =============================================================================
# Environment Description Module - Main Configuration
# =============================================================================
# This file will be expanded in tasks 9.3 and 9.4 to include Markdown template,
# checksums, and outputs.

locals {
  template_vars = {
    run_id              = var.run_id
    environment_profile = var.environment_profile
    aws_region          = var.aws_region
    availability_zone   = var.availability_zone
    timestamp           = timestamp()

    # Network
    vpc_id              = var.vpc_id
    vpc_cidr            = var.vpc_cidr
    public_subnet_id    = var.public_subnet_id
    public_subnet_cidr  = var.public_subnet_cidr
    igw_id              = var.igw_id
    route_table_ids     = var.route_table_ids

    # Security
    security_groups = var.security_groups

    # IAM
    iam_roles = var.iam_roles

    # Compute
    control_plane    = var.control_plane_metadata
    worker_nodes     = var.worker_nodes_metadata
    benchmark_runner = var.benchmark_runner_metadata

    # Load Balancing
    nlb = var.nlb_metadata

    # Storage
    ebs_volumes            = var.ebs_volumes
    storage_class_metadata = var.storage_class_metadata

    # External references
    bastion_host      = var.bastion_host_info
    run_bucket_name   = var.run_bucket_name
    artifact_prefixes = var.artifact_prefixes

    # Metadata (optional)
    kubernetes_metadata    = var.kubernetes_metadata
    observability_metadata = var.observability_metadata
    autoscaler_metadata    = var.autoscaler_metadata

    # Versioning
    opentofu_version     = "detected-at-apply-time"
    aws_provider_version = "detected-at-apply-time"
    git_commit_hash      = "not available"
  }
}

resource "local_file" "environment_json" {
  content  = templatefile("${path.module}/templates/environment-description.json.tftpl", local.template_vars)
  filename = "${var.output_path}/environment-description.json"
}

resource "local_file" "environment_md" {
  content  = templatefile("${path.module}/templates/environment-description.md.tftpl", local.template_vars)
  filename = "${var.output_path}/environment-description.md"
}

# =============================================================================
# Checksums - SHA256 hashes of generated artifact files (Requirement 23.5)
# =============================================================================

resource "local_file" "checksums" {
  content = jsonencode({
    generated_at = timestamp()
    algorithm    = "sha256"
    files = {
      "environment-description.json" = sha256(local_file.environment_json.content)
      "environment-description.md"   = sha256(local_file.environment_md.content)
    }
  })
  filename = "${var.output_path}/checksums.json"
}
