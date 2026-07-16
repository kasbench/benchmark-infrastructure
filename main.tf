# =============================================================================
# KASBench Infrastructure - Root Module Orchestration
# =============================================================================
# Instantiates all child modules in dependency order:
#   network → security, iam, storage → compute → load-balancing → environment-description
# =============================================================================

# =============================================================================
# Network Module
# =============================================================================
# Creates VPC, subnets, IGW, NAT GW, route tables, and handles AZ selection.
# No module dependencies — this is the foundation layer.

module "network" {
  source = "./modules/network"

  vpc_cidr               = var.vpc_cidr
  public_subnet_cidr     = var.public_subnet_cidr
  private_subnet_cidr    = var.private_subnet_cidr
  availability_zone_mode = var.availability_zone_mode
  availability_zone      = var.availability_zone
  aws_region             = var.aws_region
  bastion_vpc_id         = var.bastion_vpc_id
  bastion_vpc_cidr       = var.bastion_vpc_cidr
  tags                   = local.common_tags
}

# =============================================================================
# Security Module
# =============================================================================
# Creates all security groups and rules. Depends on network for VPC ID.

module "security" {
  source = "./modules/security"

  vpc_id                    = module.network.vpc_id
  bastion_ssh_cidr = var.bastion_ssh_cidr
  tags                      = local.common_tags
}

# =============================================================================
# IAM Module
# =============================================================================
# Creates IAM roles, policies, and instance profiles.
# No module dependencies — receives bucket name from root variables.

module "iam" {
  source = "./modules/iam"

  run_bucket_name     = var.run_bucket_name
  environment_profile = var.environment_profile
  tags                = local.common_tags
}

# =============================================================================
# Storage Module
# =============================================================================
# Creates pre-provisioned EBS volumes (etcd). Depends on network for AZ.

module "storage" {
  source = "./modules/storage"

  availability_zone       = module.network.selected_availability_zone
  etcd_volume_config      = var.etcd_volume_config
  environment_profile     = var.environment_profile
  debug_retention_enabled = var.debug_retention_enabled
  tags                    = local.common_tags
}

# =============================================================================
# Compute Module
# =============================================================================
# Creates all EC2 instances (benchmark-runner, control plane, workers).
# Depends on: network, security, iam, storage.

module "compute" {
  source = "./modules/compute"

  # Network references
  public_subnet_id  = module.network.public_subnet_id
  private_subnet_id = module.network.private_subnet_id
  availability_zone = module.network.selected_availability_zone

  # SSH key pair
  key_name         = aws_key_pair.fleet_key.key_name
  fleet_public_key = tls_private_key.fleet_key.public_key_openssh

  # Instance configurations
  benchmark_runner_config = var.benchmark_runner_config
  control_plane_config    = var.control_plane_config
  worker_groups           = var.worker_groups
  root_volume_config      = var.root_volume_config
  ami_amd64               = var.ami_amd64
  ami_arm64               = var.ami_arm64
  ami_runner_amd64        = var.ami_runner_amd64

  # Security group references
  benchmark_runner_sg_id = module.security.benchmark_runner_sg_id
  control_plane_sg_id    = module.security.control_plane_sg_id
  worker_node_sg_id      = module.security.worker_node_sg_id

  # IAM instance profile references
  control_plane_profile_name    = module.iam.control_plane_instance_profile_name
  worker_profile_name           = module.iam.worker_instance_profile_name
  benchmark_runner_profile_name = module.iam.benchmark_runner_instance_profile_name

  # Storage references
  etcd_volume_id = module.storage.etcd_volume_id

  # Operational
  environment_profile     = var.environment_profile
  debug_retention_enabled = var.debug_retention_enabled
  tags                    = local.common_tags
}

# =============================================================================
# Load Balancing Module
# =============================================================================
# Creates internal NLB, listeners, and target groups.
# Depends on: network, security.

module "load_balancing" {
  source = "./modules/load-balancing"

  vpc_id            = module.network.vpc_id
  public_subnet_id  = module.network.public_subnet_id
  private_subnet_id = module.network.private_subnet_id
  nlb_sg_id         = module.security.nlb_sg_id
  nlb_config        = var.nlb_config
  worker_instance_ids = concat(
    [for w in module.compute.worker_nodes_metadata.amd64 : w.instance_id],
    [for w in module.compute.worker_nodes_metadata.arm64 : w.instance_id],
  )
  tags = local.common_tags
}

# =============================================================================
# Environment Description Module
# =============================================================================
# Aggregates all module outputs into JSON and Markdown reports.
# Depends on: all other modules.

module "environment_description" {
  source = "./modules/environment-description"

  # Core identifiers
  run_id              = var.run_id
  environment_profile = var.environment_profile
  aws_region          = var.aws_region
  availability_zone   = module.network.selected_availability_zone
  output_path         = local.artifact_output_path

  # Network outputs
  vpc_id              = module.network.vpc_id
  vpc_cidr            = var.vpc_cidr
  public_subnet_id    = module.network.public_subnet_id
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_id   = module.network.private_subnet_id
  private_subnet_cidr = var.private_subnet_cidr
  igw_id              = module.network.igw_id
  nat_gw_id           = module.network.nat_gw_id
  route_table_ids     = module.network.route_table_ids

  # Security outputs
  security_groups = module.security.all_security_groups

  # IAM outputs
  iam_roles = module.iam.all_roles

  # Compute outputs
  control_plane_metadata    = module.compute.control_plane_metadata
  worker_nodes_metadata     = module.compute.worker_nodes_metadata
  benchmark_runner_metadata = module.compute.benchmark_runner_metadata

  # Load balancing outputs
  nlb_metadata = module.load_balancing.nlb_metadata

  # Storage outputs
  ebs_volumes            = module.storage.all_volumes
  storage_class_metadata = module.storage.storage_class_metadata

  # External references
  bastion_host_info = var.bastion_host_info
  run_bucket_name   = var.run_bucket_name
  artifact_prefixes = var.artifact_prefixes

  # Metadata (pass-through)
  kubernetes_metadata    = var.kubernetes_metadata
  observability_metadata = var.observability_metadata
  autoscaler_metadata    = var.autoscaler_metadata
}
