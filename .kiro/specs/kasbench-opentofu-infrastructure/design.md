# Design Document

## Overview

This document describes the technical design for implementing the KASBench AWS infrastructure as OpenTofu infrastructure-as-code. The design covers the repository structure, module architecture, inter-module interfaces, data models, configuration strategy, and environment description generation. The implementation uses a root module at the repository root with seven child modules, two environment profiles via tfvars files, and pure HCL-based environment report generation.

## Architecture

The OpenTofu stack follows a flat root-module pattern with child modules for separation of concerns:

```
(repo root)
├── main.tf                  # Root module orchestration
├── variables.tf             # All root-level input variables
├── outputs.tf               # All root-level outputs
├── providers.tf             # Provider configuration
├── versions.tf              # Required providers and version constraints
├── modules/
│   ├── network/             # VPC, subnets, IGW, NAT GW, route tables, AZ selection
│   ├── security/            # Security groups and rules
│   ├── iam/                 # IAM roles, policies, instance profiles
│   ├── compute/             # EC2 instances (CP, workers, benchmark-runner)
│   ├── load-balancing/      # Internal NLB, listeners, target groups
│   ├── storage/             # Pre-created EBS volumes, StorageClass metadata
│   └── environment-description/  # JSON + Markdown report generation
├── environments/
│   ├── small.tfvars         # Small profile configuration
│   └── benchmark.tfvars    # Full benchmark profile configuration
└── artifacts/
    └── .gitkeep             # Output directory for generated reports
```

### Module Dependency Graph

```
main.tf (root)
  ├── network          (no module dependencies)
  ├── security         (depends on: network)
  ├── iam              (depends on: none, receives bucket name from variables)
  ├── compute          (depends on: network, security, iam, storage)
  ├── load-balancing   (depends on: network, security, compute)
  ├── storage          (depends on: network)
  └── environment-description (depends on: all other modules' outputs)
```

### Data Flow

1. Root `variables.tf` accepts all configuration from tfvars
2. `main.tf` instantiates modules in dependency order, passing variables and cross-module outputs
3. Each module produces outputs consumed by downstream modules
4. `environment-description` module aggregates all outputs into JSON and Markdown reports
5. Root `outputs.tf` exposes key values for the Kubernetes bootstrap process

## Components and Interfaces

### 1. Root Module (Repository Root)

#### providers.tf

```hcl
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
```

#### versions.tf

```hcl
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
```

#### main.tf (Module Instantiation)

```hcl
module "network" {
  source = "./modules/network"

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone_mode = var.availability_zone_mode
  availability_zone      = var.availability_zone
  aws_region             = var.aws_region
  tags                   = local.common_tags
}

module "security" {
  source = "./modules/security"

  vpc_id                    = module.network.vpc_id
  bastion_security_group_id = var.bastion_security_group_id
  tags                      = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  run_bucket_name     = var.run_bucket_name
  environment_profile = var.environment_profile
  tags                = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  availability_zone       = module.network.selected_availability_zone
  etcd_volume_config      = var.etcd_volume_config
  environment_profile     = var.environment_profile
  debug_retention_enabled = var.debug_retention_enabled
  tags                    = local.common_tags
}

module "compute" {
  source = "./modules/compute"

  public_subnet_id  = module.network.public_subnet_id
  private_subnet_id = module.network.private_subnet_id
  availability_zone = module.network.selected_availability_zone

  benchmark_runner_config = var.benchmark_runner_config
  control_plane_config    = var.control_plane_config
  worker_groups           = var.worker_groups
  root_volume_config      = var.root_volume_config
  ami_amd64               = var.ami_amd64
  ami_arm64               = var.ami_arm64

  benchmark_runner_sg_id    = module.security.benchmark_runner_sg_id
  control_plane_sg_id       = module.security.control_plane_sg_id
  worker_node_sg_id         = module.security.worker_node_sg_id
  control_plane_profile_name = module.iam.control_plane_instance_profile_name
  worker_profile_name        = module.iam.worker_instance_profile_name
  benchmark_runner_profile_name = module.iam.benchmark_runner_instance_profile_name

  etcd_volume_id          = module.storage.etcd_volume_id
  environment_profile     = var.environment_profile
  debug_retention_enabled = var.debug_retention_enabled
  tags                    = local.common_tags
}

module "load_balancing" {
  source = "./modules/load-balancing"

  vpc_id            = module.network.vpc_id
  private_subnet_id = module.network.private_subnet_id
  nlb_sg_id         = module.security.nlb_sg_id
  nlb_config        = var.nlb_config
  tags              = local.common_tags
}

module "environment_description" {
  source = "./modules/environment-description"

  run_id              = var.run_id
  environment_profile = var.environment_profile
  aws_region          = var.aws_region
  availability_zone   = module.network.selected_availability_zone
  output_path         = var.artifact_output_path

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
  control_plane_metadata  = module.compute.control_plane_metadata
  worker_nodes_metadata   = module.compute.worker_nodes_metadata
  benchmark_runner_metadata = module.compute.benchmark_runner_metadata

  # Load balancing outputs
  nlb_metadata = module.load_balancing.nlb_metadata

  # Storage outputs
  ebs_volumes         = module.storage.all_volumes
  storage_class_metadata = module.storage.storage_class_metadata

  # External references
  bastion_host_info   = var.bastion_host_info
  run_bucket_name     = var.run_bucket_name
  artifact_prefixes   = var.artifact_prefixes

  # Metadata
  kubernetes_metadata    = var.kubernetes_metadata
  observability_metadata = var.observability_metadata
  autoscaler_metadata    = var.autoscaler_metadata
}
```

### 2. Network Module (`modules/network/`)

**Purpose:** Creates the VPC, subnets, Internet Gateway, NAT Gateway, route tables, and handles AZ selection.

#### AZ Selection Strategy

```hcl
# modules/network/az.tf

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_shuffle" "az" {
  count        = var.availability_zone_mode == "random" ? 1 : 0
  input        = data.aws_availability_zones.available.names
  result_count = 1
}

locals {
  selected_az = (
    var.availability_zone_mode == "explicit"
    ? var.availability_zone
    : random_shuffle.az[0].result[0]
  )
}
```

The `random_shuffle` resource persists its result in OpenTofu state. Subsequent `tofu plan` or `tofu apply` operations reuse the same AZ without re-randomization, satisfying the reproducibility requirement.

#### Network Resources

```hcl
# modules/network/main.tf

resource "aws_vpc" "benchmark" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "kasbench-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.benchmark.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.selected_az
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "kasbench-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.benchmark.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.selected_az
  tags              = merge(var.tags, { Name = "kasbench-private" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.benchmark.id
  tags   = merge(var.tags, { Name = "kasbench-igw" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "kasbench-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = merge(var.tags, { Name = "kasbench-nat-gw" })
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.benchmark.id
  tags   = merge(var.tags, { Name = "kasbench-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.benchmark.id
  tags   = merge(var.tags, { Name = "kasbench-private-rt" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
```

#### Network Module Outputs

```hcl
output "vpc_id" { value = aws_vpc.benchmark.id }
output "public_subnet_id" { value = aws_subnet.public.id }
output "private_subnet_id" { value = aws_subnet.private.id }
output "selected_availability_zone" { value = local.selected_az }
output "igw_id" { value = aws_internet_gateway.main.id }
output "nat_gw_id" { value = aws_nat_gateway.main.id }
output "route_table_ids" {
  value = {
    public  = aws_route_table.public.id
    private = aws_route_table.private.id
  }
}
```

### 3. Security Module (`modules/security/`)

**Purpose:** Creates all security groups and their ingress/egress rules. References the external bastion security group for SSH access control.

#### Security Group Design

| Security Group | Inbound Sources | Key Ports |
|---|---|---|
| Benchmark-Runner SG | Bastion SG (SSH/22) | 22 |
| NLB SG | Benchmark-Runner SG | Configurable listener ports |
| Control-Plane SG | Worker SG (kubelet), Bastion SG (SSH), self (etcd) | 6443, 2379-2380, 10250, 22 |
| Worker-Node SG | CP SG (kubelet), self (overlay, NodePort), Bastion SG (SSH) | 10250, 30000-32767, 9090, 9100, 22 |

```hcl
# modules/security/main.tf

resource "aws_security_group" "benchmark_runner" {
  name_prefix = "kasbench-runner-"
  vpc_id      = var.vpc_id
  description = "Benchmark-runner: SSH from bastion only"
  tags        = merge(var.tags, { Name = "kasbench-runner-sg" })
}

resource "aws_security_group_rule" "runner_ssh_in" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = var.bastion_security_group_id
  security_group_id        = aws_security_group.benchmark_runner.id
  description              = "SSH from bastion host"
}

resource "aws_security_group_rule" "runner_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.benchmark_runner.id
  description       = "Allow all outbound"
}

resource "aws_security_group" "nlb" {
  name_prefix = "kasbench-nlb-"
  vpc_id      = var.vpc_id
  description = "Internal NLB: traffic from benchmark-runner only"
  tags        = merge(var.tags, { Name = "kasbench-nlb-sg" })
}

resource "aws_security_group_rule" "nlb_from_runner" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.benchmark_runner.id
  security_group_id        = aws_security_group.nlb.id
  description              = "All TCP from benchmark-runner"
}

resource "aws_security_group" "control_plane" {
  name_prefix = "kasbench-cp-"
  vpc_id      = var.vpc_id
  description = "Kubernetes control plane"
  tags        = merge(var.tags, { Name = "kasbench-cp-sg" })
}

# Control plane rules: API server, etcd, kubelet, SSH
resource "aws_security_group_rule" "cp_api_from_workers" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker_node.id
  security_group_id        = aws_security_group.control_plane.id
  description              = "Kubernetes API from workers"
}

resource "aws_security_group_rule" "cp_api_from_runner" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.benchmark_runner.id
  security_group_id        = aws_security_group.control_plane.id
  description              = "Kubernetes API from benchmark-runner"
}

resource "aws_security_group_rule" "cp_etcd" {
  type              = "ingress"
  from_port         = 2379
  to_port           = 2380
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.control_plane.id
  description       = "etcd peer and client"
}

resource "aws_security_group_rule" "cp_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker_node.id
  security_group_id        = aws_security_group.control_plane.id
  description              = "kubelet API from workers"
}

resource "aws_security_group_rule" "cp_ssh" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = var.bastion_security_group_id
  security_group_id        = aws_security_group.control_plane.id
  description              = "SSH from bastion"
}

resource "aws_security_group" "worker_node" {
  name_prefix = "kasbench-worker-"
  vpc_id      = var.vpc_id
  description = "Kubernetes worker nodes"
  tags        = merge(var.tags, { Name = "kasbench-worker-sg" })
}

# Worker node rules: kubelet, NodePort, inter-node, observability, SSH
resource "aws_security_group_rule" "worker_kubelet_from_cp" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.worker_node.id
  description              = "kubelet from control plane"
}

resource "aws_security_group_rule" "worker_nodeport" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.worker_node.id
  description       = "NodePort range inter-node"
}

resource "aws_security_group_rule" "worker_prometheus" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.worker_node.id
  description       = "Prometheus scraping"
}

resource "aws_security_group_rule" "worker_node_exporter" {
  type              = "ingress"
  from_port         = 9100
  to_port           = 9100
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.worker_node.id
  description       = "Node exporter"
}

resource "aws_security_group_rule" "worker_ssh" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = var.bastion_security_group_id
  security_group_id        = aws_security_group.worker_node.id
  description              = "SSH from bastion"
}

resource "aws_security_group_rule" "worker_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker_node.id
  description       = "Allow all outbound"
}
```

#### Security Module Outputs

```hcl
output "benchmark_runner_sg_id" { value = aws_security_group.benchmark_runner.id }
output "nlb_sg_id" { value = aws_security_group.nlb.id }
output "control_plane_sg_id" { value = aws_security_group.control_plane.id }
output "worker_node_sg_id" { value = aws_security_group.worker_node.id }
output "all_security_groups" {
  value = {
    benchmark_runner = {
      id    = aws_security_group.benchmark_runner.id
      name  = aws_security_group.benchmark_runner.name
      rules = "SSH from bastion only; all egress"
    }
    nlb = {
      id    = aws_security_group.nlb.id
      name  = aws_security_group.nlb.name
      rules = "TCP from benchmark-runner only"
    }
    control_plane = {
      id    = aws_security_group.control_plane.id
      name  = aws_security_group.control_plane.name
      rules = "6443 from workers/runner; 2379-2380 self; 10250 from workers; SSH from bastion"
    }
    worker_node = {
      id    = aws_security_group.worker_node.id
      name  = aws_security_group.worker_node.name
      rules = "10250 from CP; 30000-32767 self; 9090/9100 self; SSH from bastion; all egress"
    }
  }
}
```

### 4. IAM Module (`modules/iam/`)

**Purpose:** Creates IAM roles, policies, and instance profiles for the control plane, worker nodes, and benchmark-runner with least-privilege permissions.

#### IAM Role Structure

| Role | Permissions | Scope |
|---|---|---|
| Control Plane | EC2 describe, EBS attach/detach | Own instance volumes |
| Worker Node | EC2 describe, EBS CSI (create/attach/delete volumes), ECR read | Cluster resources |
| Benchmark Runner | S3 write to run bucket | Specific bucket ARN |

```hcl
# modules/iam/main.tf

# Control Plane Role
resource "aws_iam_role" "control_plane" {
  name_prefix        = "kasbench-cp-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "control_plane" {
  name_prefix = "kasbench-cp-"
  policy      = data.aws_iam_policy_document.control_plane_policy.json
}

data "aws_iam_policy_document" "control_plane_policy" {
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "EBSAttach"
    effect = "Allow"
    actions = [
      "ec2:AttachVolume",
      "ec2:DetachVolume",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["KASBench"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "control_plane" {
  role       = aws_iam_role.control_plane.name
  policy_arn = aws_iam_policy.control_plane.arn
}

resource "aws_iam_instance_profile" "control_plane" {
  name_prefix = "kasbench-cp-"
  role        = aws_iam_role.control_plane.name
}

# Worker Node Role (includes EBS CSI permissions)
resource "aws_iam_role" "worker_node" {
  name_prefix        = "kasbench-worker-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

resource "aws_iam_policy" "worker_node" {
  name_prefix = "kasbench-worker-"
  policy      = data.aws_iam_policy_document.worker_node_policy.json
}

data "aws_iam_policy_document" "worker_node_policy" {
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSnapshots",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "EBSCSIDriver"
    effect = "Allow"
    actions = [
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:CreateTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["KASBench"]
    }
  }
  statement {
    sid    = "ECRRead"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "worker_node" {
  role       = aws_iam_role.worker_node.name
  policy_arn = aws_iam_policy.worker_node.arn
}

resource "aws_iam_instance_profile" "worker_node" {
  name_prefix = "kasbench-worker-"
  role        = aws_iam_role.worker_node.name
}

# Benchmark Runner Role
resource "aws_iam_role" "benchmark_runner" {
  name_prefix        = "kasbench-runner-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

resource "aws_iam_policy" "benchmark_runner" {
  name_prefix = "kasbench-runner-"
  policy      = data.aws_iam_policy_document.benchmark_runner_policy.json
}

data "aws_iam_policy_document" "benchmark_runner_policy" {
  statement {
    sid    = "S3WriteRunBucket"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.run_bucket_name}",
      "arn:aws:s3:::${var.run_bucket_name}/*",
    ]
  }
}

resource "aws_iam_role_policy_attachment" "benchmark_runner" {
  role       = aws_iam_role.benchmark_runner.name
  policy_arn = aws_iam_policy.benchmark_runner.arn
}

resource "aws_iam_instance_profile" "benchmark_runner" {
  name_prefix = "kasbench-runner-"
  role        = aws_iam_role.benchmark_runner.name
}
```

#### IAM Module Outputs

```hcl
output "control_plane_instance_profile_name" { value = aws_iam_instance_profile.control_plane.name }
output "worker_instance_profile_name" { value = aws_iam_instance_profile.worker_node.name }
output "benchmark_runner_instance_profile_name" { value = aws_iam_instance_profile.benchmark_runner.name }
output "all_roles" {
  value = {
    control_plane    = { role_name = aws_iam_role.control_plane.name, profile_name = aws_iam_instance_profile.control_plane.name }
    worker_node      = { role_name = aws_iam_role.worker_node.name, profile_name = aws_iam_instance_profile.worker_node.name }
    benchmark_runner = { role_name = aws_iam_role.benchmark_runner.name, profile_name = aws_iam_instance_profile.benchmark_runner.name }
  }
}
```

### 5. Compute Module (`modules/compute/`)

**Purpose:** Creates all EC2 instances — benchmark-runner, control plane, and worker node groups. Handles architecture-specific AMI selection, tagging, and root volume configuration.

#### Benchmark-Runner Instance

```hcl
# modules/compute/benchmark_runner.tf

resource "aws_instance" "benchmark_runner" {
  ami                         = var.ami_amd64
  instance_type               = var.benchmark_runner_config.instance_type
  subnet_id                   = var.public_subnet_id
  availability_zone           = var.availability_zone
  vpc_security_group_ids      = [var.benchmark_runner_sg_id]
  iam_instance_profile        = var.benchmark_runner_profile_name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name             = "kasbench-benchmark-runner"
    "kubernetes-role" = "benchmark-runner"
  })
}
```

#### Control Plane Instance

```hcl
# modules/compute/control_plane.tf

resource "aws_instance" "control_plane" {
  ami                    = var.ami_amd64
  instance_type          = var.control_plane_config.instance_type
  subnet_id              = var.private_subnet_id
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [var.control_plane_sg_id]
  iam_instance_profile   = var.control_plane_profile_name

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name              = "kasbench-control-plane"
    "kubernetes-role" = "control-plane"
    "kubernetes-arch" = "amd64"
  })

  lifecycle {
    prevent_destroy = false
  }
}

# Attach pre-created etcd volume
resource "aws_volume_attachment" "etcd" {
  device_name = "/dev/xvdf"
  volume_id   = var.etcd_volume_id
  instance_id = aws_instance.control_plane.id
}
```

#### Worker Node Groups

```hcl
# modules/compute/workers.tf

resource "aws_instance" "worker_amd64" {
  count = var.worker_groups.amd64.count

  ami                    = var.ami_amd64
  instance_type          = var.worker_groups.amd64.instance_type
  subnet_id              = var.private_subnet_id
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [var.worker_node_sg_id]
  iam_instance_profile   = var.worker_profile_name

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name              = "kasbench-worker-amd64-${count.index}"
    "kubernetes-role" = "worker"
    "kubernetes-arch" = "amd64"
    "node-group"      = "amd64"
    "node-index"      = tostring(count.index)
  })

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_instance" "worker_arm64" {
  count = var.worker_groups.arm64.count

  ami                    = var.ami_arm64
  instance_type          = var.worker_groups.arm64.instance_type
  subnet_id              = var.private_subnet_id
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [var.worker_node_sg_id]
  iam_instance_profile   = var.worker_profile_name

  root_block_device {
    volume_type           = var.root_volume_config.type
    volume_size           = var.root_volume_config.size_gib
    iops                  = var.root_volume_config.iops
    throughput            = var.root_volume_config.throughput
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name              = "kasbench-worker-arm64-${count.index}"
    "kubernetes-role" = "worker"
    "kubernetes-arch" = "arm64"
    "node-group"      = "arm64"
    "node-index"      = tostring(count.index)
  })

  lifecycle {
    prevent_destroy = false
  }
}
```

#### Debug Retention Lifecycle

The `prevent_destroy` lifecycle rule is controlled dynamically. Since HCL does not support conditional lifecycle blocks natively, the implementation uses a two-resource pattern with `count`:

```hcl
# When debug_retention_enabled = true AND environment_profile = "small",
# use a separate resource definition with prevent_destroy = true.
# The root main.tf selects which compute module variant to use based on these conditions.
# For simplicity, the benchmark profile always ignores debug_retention_enabled.

locals {
  apply_debug_retention = var.debug_retention_enabled && var.environment_profile == "small"
}
```

Note: Since OpenTofu/Terraform does not support dynamic `lifecycle` blocks, the actual implementation will use `precondition` blocks or a wrapper script that fails `tofu destroy` when debug retention is active for the small profile. The benchmark profile always permits destruction regardless of the flag.

#### Compute Module Outputs

```hcl
output "control_plane_metadata" {
  value = {
    instance_id   = aws_instance.control_plane.id
    private_ip    = aws_instance.control_plane.private_ip
    instance_type = aws_instance.control_plane.instance_type
    ami_id        = aws_instance.control_plane.ami
    architecture  = "amd64"
    subnet_id     = aws_instance.control_plane.subnet_id
    az            = aws_instance.control_plane.availability_zone
    root_volume_id = aws_instance.control_plane.root_block_device[0].volume_id
  }
}

output "worker_nodes_metadata" {
  value = {
    amd64 = [for i, inst in aws_instance.worker_amd64 : {
      instance_id   = inst.id
      private_ip    = inst.private_ip
      instance_type = inst.instance_type
      ami_id        = inst.ami
      architecture  = "amd64"
      subnet_id     = inst.subnet_id
      az            = inst.availability_zone
      root_volume_id = inst.root_block_device[0].volume_id
      node_index    = i
    }]
    arm64 = [for i, inst in aws_instance.worker_arm64 : {
      instance_id   = inst.id
      private_ip    = inst.private_ip
      instance_type = inst.instance_type
      ami_id        = inst.ami
      architecture  = "arm64"
      subnet_id     = inst.subnet_id
      az            = inst.availability_zone
      root_volume_id = inst.root_block_device[0].volume_id
      node_index    = i
    }]
  }
}

output "benchmark_runner_metadata" {
  value = {
    instance_id   = aws_instance.benchmark_runner.id
    public_ip     = aws_instance.benchmark_runner.public_ip
    private_ip    = aws_instance.benchmark_runner.private_ip
    instance_type = aws_instance.benchmark_runner.instance_type
    ami_id        = aws_instance.benchmark_runner.ami
    subnet_id     = aws_instance.benchmark_runner.subnet_id
    az            = aws_instance.benchmark_runner.availability_zone
  }
}
```

### 6. Load Balancing Module (`modules/load-balancing/`)

**Purpose:** Creates the internal Network Load Balancer, listeners, and target groups. The NLB routes benchmark traffic from the benchmark-runner to the Kubernetes Gateway API / ingress controller.

```hcl
# modules/load-balancing/main.tf

resource "aws_lb" "internal" {
  name_prefix        = "kasb-"
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.private_subnet_id]
  security_groups    = [var.nlb_sg_id]

  tags = merge(var.tags, { Name = "kasbench-internal-nlb" })
}

resource "aws_lb_target_group" "ingress" {
  for_each = { for l in var.nlb_config.listeners : l.name => l }

  name_prefix = "kasb-"
  port        = each.value.target_port
  protocol    = each.value.protocol
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    port                = each.value.health_check_port
    protocol            = each.value.health_check_protocol
    path                = each.value.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(var.tags, { Name = "kasbench-tg-${each.key}" })
}

resource "aws_lb_listener" "ingress" {
  for_each = { for l in var.nlb_config.listeners : l.name => l }

  load_balancer_arn = aws_lb.internal.arn
  port              = each.value.listener_port
  protocol          = each.value.protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress[each.key].arn
  }

  tags = merge(var.tags, { Name = "kasbench-listener-${each.key}" })
}
```

#### Load Balancing Module Outputs

```hcl
output "nlb_metadata" {
  value = {
    dns_name   = aws_lb.internal.dns_name
    arn        = aws_lb.internal.arn
    scheme     = "internal"
    listeners  = { for k, l in aws_lb_listener.ingress : k => {
      port     = l.port
      protocol = l.protocol
    }}
    target_groups = { for k, tg in aws_lb_target_group.ingress : k => {
      arn  = tg.arn
      port = tg.port
    }}
  }
}
```

### 7. Storage Module (`modules/storage/`)

**Purpose:** Pre-creates dedicated EBS volumes for etcd/control-plane state and outputs StorageClass metadata for the EBS CSI driver to dynamically provision workload volumes.

#### Pre-Created EBS Volumes

```hcl
# modules/storage/main.tf

resource "aws_ebs_volume" "etcd" {
  availability_zone = var.availability_zone
  size              = var.etcd_volume_config.size_gib
  type              = var.etcd_volume_config.type
  iops              = var.etcd_volume_config.iops
  throughput        = var.etcd_volume_config.throughput
  encrypted         = true

  tags = merge(var.tags, {
    Name     = "kasbench-etcd"
    Workload = "etcd"
  })
}
```

#### StorageClass Metadata Outputs

The storage module does not create Kubernetes StorageClass resources (that is the bootstrap process's responsibility). Instead, it outputs the metadata needed to configure them:

```hcl
# modules/storage/outputs.tf

output "etcd_volume_id" { value = aws_ebs_volume.etcd.id }

output "all_volumes" {
  value = {
    etcd = {
      volume_id  = aws_ebs_volume.etcd.id
      size_gib   = aws_ebs_volume.etcd.size
      type       = aws_ebs_volume.etcd.type
      iops       = aws_ebs_volume.etcd.iops
      throughput = aws_ebs_volume.etcd.throughput
      az         = aws_ebs_volume.etcd.availability_zone
      workload   = "etcd"
    }
  }
}

output "storage_class_metadata" {
  description = "Metadata for Kubernetes StorageClass configuration by bootstrap process"
  value = {
    default_workload_storage = {
      volume_type = "gp3"
      fs_type     = "ext4"
      encrypted   = true
      description = "Default StorageClass for PostgreSQL, Kafka, Prometheus PVCs"
    }
    high_iops_storage = {
      volume_type = "gp3"
      iops        = 6000
      throughput  = 250
      fs_type     = "ext4"
      encrypted   = true
      description = "High-IOPS StorageClass for Kafka and PostgreSQL"
    }
  }
}
```

### 8. Environment Description Module (`modules/environment-description/`)

**Purpose:** Generates JSON and Markdown environment reports using `templatefile()` and `local_file` resources. No external scripts.

#### Template Strategy

The module uses two template files:
- `templates/environment-description.json.tftpl` — JSON report
- `templates/environment-description.md.tftpl` — Markdown report

Both templates receive the same set of variables containing all infrastructure metadata.

```hcl
# modules/environment-description/main.tf

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
    private_subnet_id   = var.private_subnet_id
    private_subnet_cidr = var.private_subnet_cidr
    igw_id              = var.igw_id
    nat_gw_id           = var.nat_gw_id
    route_table_ids     = var.route_table_ids

    # Security
    security_groups = var.security_groups

    # IAM
    iam_roles = var.iam_roles

    # Compute
    control_plane  = var.control_plane_metadata
    worker_nodes   = var.worker_nodes_metadata
    benchmark_runner = var.benchmark_runner_metadata

    # Load Balancing
    nlb = var.nlb_metadata

    # Storage
    ebs_volumes         = var.ebs_volumes
    storage_class_metadata = var.storage_class_metadata

    # External references
    bastion_host    = var.bastion_host_info
    run_bucket_name = var.run_bucket_name
    artifact_prefixes = var.artifact_prefixes

    # Metadata
    kubernetes_metadata    = var.kubernetes_metadata
    observability_metadata = var.observability_metadata
    autoscaler_metadata    = var.autoscaler_metadata

    # Versioning
    opentofu_version    = "detected-at-apply-time"
    aws_provider_version = "detected-at-apply-time"
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

# Checksums for reproducibility
resource "local_file" "checksums" {
  content = jsonencode({
    json_sha256 = sha256(local_file.environment_json.content)
    md_sha256   = sha256(local_file.environment_md.content)
  })
  filename = "${var.output_path}/checksums.json"
}
```

#### JSON Template Structure (abbreviated)

```json
// templates/environment-description.json.tftpl
{
  "kasbench_environment": {
    "metadata": {
      "run_id": "${run_id}",
      "environment_profile": "${environment_profile}",
      "created_at": "${timestamp}",
      "opentofu_version": "${opentofu_version}",
      "aws_provider_version": "${aws_provider_version}"
    },
    "infrastructure": {
      "region": "${aws_region}",
      "availability_zone": "${availability_zone}",
      "vpc": { "id": "${vpc_id}", "cidr": "${vpc_cidr}" },
      "subnets": { ... },
      "gateways": { ... },
      "route_tables": ${jsonencode(route_table_ids)},
      "security_groups": ${jsonencode(security_groups)},
      "iam_roles": ${jsonencode(iam_roles)},
      "compute": {
        "control_plane": ${jsonencode(control_plane)},
        "worker_nodes": ${jsonencode(worker_nodes)},
        "benchmark_runner": ${jsonencode(benchmark_runner)}
      },
      "load_balancer": ${jsonencode(nlb)},
      "storage": {
        "ebs_volumes": ${jsonencode(ebs_volumes)},
        "storage_classes": ${jsonencode(storage_class_metadata)}
      }
    },
    "external_dependencies": {
      "bastion_host": ${jsonencode(bastion_host)},
      "run_bucket": "${run_bucket_name}",
      "artifact_prefixes": ${jsonencode(artifact_prefixes)}
    },
    "kubernetes_metadata": ${jsonencode(kubernetes_metadata)},
    "observability_metadata": ${jsonencode(observability_metadata)},
    "autoscaler_metadata": ${jsonencode(autoscaler_metadata)}
  }
}
```

### Root Module Input Variables

```hcl
# Core configuration
variable "environment_profile" {
  type        = string
  description = "Environment profile: small or benchmark"
  validation {
    condition     = contains(["small", "benchmark"], var.environment_profile)
    error_message = "environment_profile must be 'small' or 'benchmark'"
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-1"
}

variable "availability_zone_mode" {
  type        = string
  description = "AZ selection mode: explicit or random"
  validation {
    condition     = contains(["explicit", "random"], var.availability_zone_mode)
    error_message = "availability_zone_mode must be 'explicit' or 'random'"
  }
}

variable "availability_zone" {
  type        = string
  description = "Explicit AZ (required when mode is explicit)"
  default     = null
}

variable "run_id" {
  type        = string
  description = "Unique identifier for this benchmark run"
}

variable "owner" {
  type        = string
  description = "Owner tag value for cost allocation"
}

# Network
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

# External dependencies
variable "bastion_security_group_id" {
  type        = string
  description = "Security group ID of the external bastion/controller host"
}

variable "bastion_host_info" {
  type = object({
    instance_id = optional(string)
    private_ip  = optional(string)
    name        = optional(string)
  })
  description = "Bastion host reference information"
  default     = {}
}

variable "run_bucket_name" {
  type        = string
  description = "Name of the pre-existing S3 run bucket"
}

variable "artifact_prefixes" {
  type = object({
    environment = string
    reports     = string
    trials      = string
  })
  default = {
    environment = "environment/"
    reports     = "reports/"
    trials      = "trials/"
  }
}

# AMIs
variable "ami_amd64" {
  type        = string
  description = "AMI ID for amd64 instances"
}

variable "ami_arm64" {
  type        = string
  description = "AMI ID for arm64 instances"
}

# Compute
variable "benchmark_runner_config" {
  type = object({
    instance_type = string
  })
  default = { instance_type = "t3.medium" }
}

variable "control_plane_config" {
  type = object({
    instance_type = string
  })
  default = { instance_type = "m8i.xlarge" }
}

variable "worker_groups" {
  type = object({
    amd64 = object({
      instance_type = string
      count         = number
    })
    arm64 = object({
      instance_type = string
      count         = number
    })
  })
  default = {
    amd64 = { instance_type = "c8i.4xlarge", count = 5 }
    arm64 = { instance_type = "c8g.4xlarge", count = 5 }
  }
}

variable "root_volume_config" {
  type = object({
    type       = string
    size_gib   = number
    iops       = optional(number)
    throughput = optional(number)
  })
  default = {
    type     = "gp3"
    size_gib = 100
  }
}

# Storage
variable "etcd_volume_config" {
  type = object({
    size_gib   = number
    type       = string
    iops       = optional(number)
    throughput = optional(number)
  })
  default = {
    size_gib = 50
    type     = "gp3"
    iops     = 3000
    throughput = 125
  }
}

# NLB
variable "nlb_config" {
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
  default = {
    listeners = [{
      name                  = "http"
      listener_port         = 80
      target_port           = 30080
      protocol              = "TCP"
      health_check_port     = 30080
      health_check_protocol = "TCP"
      health_check_path     = null
    }]
  }
}

# Kubernetes metadata (pass-through for environment description)
variable "kubernetes_metadata" {
  type = object({
    version           = optional(string)
    cni_plugin        = optional(string)
    cni_version       = optional(string)
    kube_proxy_mode   = optional(string)
    container_runtime = optional(string)
    helm_version      = optional(string)
  })
  default = null
}

variable "observability_metadata" {
  type = object({
    prometheus_retention = optional(string)
    jaeger_retention     = optional(string)
    scrape_interval      = optional(string)
  })
  default = null
}

variable "autoscaler_metadata" {
  type = object({
    hpa_enabled  = optional(bool)
    vpa_enabled  = optional(bool)
    keda_enabled = optional(bool)
    autoscaler_under_test = optional(string)
  })
  default = null
}

# Operational
variable "debug_retention_enabled" {
  type        = bool
  description = "Prevent destruction of EC2/EBS in small profile for debugging"
  default     = false
}

variable "artifact_output_path" {
  type        = string
  description = "Local path for generated environment description files"
  default     = null  # Computed as artifacts/<run_id>/ if not set
}

variable "trial_id" {
  type        = string
  description = "Optional trial ID for tagging"
  default     = null
}
```

### Root Module Outputs

```hcl
# outputs.tf — Key outputs for Kubernetes bootstrap handoff

output "control_plane" {
  description = "Control plane instance details for bootstrap"
  value       = module.compute.control_plane_metadata
}

output "worker_nodes" {
  description = "Worker node details grouped by architecture"
  value       = module.compute.worker_nodes_metadata
}

output "benchmark_runner" {
  description = "Benchmark runner instance details"
  value       = module.compute.benchmark_runner_metadata
}

output "nlb" {
  description = "Internal NLB details for bootstrap and validation"
  value       = module.load_balancing.nlb_metadata
}

output "security_groups" {
  description = "All security group IDs"
  value = {
    benchmark_runner = module.security.benchmark_runner_sg_id
    nlb              = module.security.nlb_sg_id
    control_plane    = module.security.control_plane_sg_id
    worker_node      = module.security.worker_node_sg_id
  }
}

output "storage" {
  description = "EBS volumes and StorageClass metadata"
  value = {
    volumes         = module.storage.all_volumes
    storage_classes = module.storage.storage_class_metadata
  }
}

output "network" {
  description = "Network resource IDs"
  value = {
    vpc_id              = module.network.vpc_id
    public_subnet_id    = module.network.public_subnet_id
    private_subnet_id   = module.network.private_subnet_id
    availability_zone   = module.network.selected_availability_zone
    igw_id              = module.network.igw_id
    nat_gw_id           = module.network.nat_gw_id
  }
}

output "run_bucket_name" {
  description = "S3 run bucket name for artifact uploads"
  value       = var.run_bucket_name
}

output "run_id" {
  description = "Benchmark run identifier"
  value       = var.run_id
}

output "environment_description_paths" {
  description = "Paths to generated environment description files"
  value = {
    json      = module.environment_description.json_path
    markdown  = module.environment_description.markdown_path
    checksums = module.environment_description.checksums_path
  }
}
```

## Data Models

### Environment Profile Configuration (tfvars)

#### `environments/benchmark.tfvars`

```hcl
environment_profile = "benchmark"
aws_region          = "us-east-1"
availability_zone_mode = "random"
availability_zone      = null

run_id          = "kasbench-YYYYMMDD-HHMMSS"
owner           = "dissertation-author"
run_bucket_name = "kasbench-run-YYYYMMDD-HHMMSS"

vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"

bastion_security_group_id = "sg-REPLACE"
bastion_host_info = {
  instance_id = "i-REPLACE"
  private_ip  = "REPLACE"
  name        = "kasbench-bastion"
}

ami_amd64 = "ami-REPLACE"
ami_arm64 = "ami-REPLACE"

benchmark_runner_config = { instance_type = "t3.medium" }
control_plane_config    = { instance_type = "m8i.xlarge" }

worker_groups = {
  amd64 = { instance_type = "c8i.4xlarge", count = 5 }
  arm64 = { instance_type = "c8g.4xlarge", count = 5 }
}

root_volume_config = {
  type     = "gp3"
  size_gib = 100
}

etcd_volume_config = {
  size_gib   = 50
  type       = "gp3"
  iops       = 3000
  throughput = 125
}

nlb_config = {
  listeners = [{
    name                  = "http"
    listener_port         = 80
    target_port           = 30080
    protocol              = "TCP"
    health_check_port     = 30080
    health_check_protocol = "TCP"
    health_check_path     = null
  }]
}

debug_retention_enabled = false
```

#### `environments/small.tfvars`

```hcl
environment_profile = "small"
aws_region          = "us-east-1"
availability_zone_mode = "explicit"
availability_zone      = "us-east-1a"

run_id          = "kasbench-dev-YYYYMMDD-HHMMSS"
owner           = "dissertation-author"
run_bucket_name = "kasbench-dev-YYYYMMDD-HHMMSS"

vpc_cidr            = "10.10.0.0/16"
public_subnet_cidr  = "10.10.1.0/24"
private_subnet_cidr = "10.10.2.0/24"

bastion_security_group_id = "sg-REPLACE"
bastion_host_info = {
  instance_id = "i-REPLACE"
  private_ip  = "REPLACE"
  name        = "kasbench-bastion-dev"
}

ami_amd64 = "ami-REPLACE"
ami_arm64 = "ami-REPLACE"

benchmark_runner_config = { instance_type = "t3.medium" }
control_plane_config    = { instance_type = "t3.large" }

worker_groups = {
  amd64 = { instance_type = "t3.large", count = 1 }
  arm64 = { instance_type = "t4g.large", count = 1 }
}

root_volume_config = {
  type     = "gp3"
  size_gib = 50
}

etcd_volume_config = {
  size_gib   = 20
  type       = "gp3"
  iops       = 3000
  throughput = 125
}

nlb_config = {
  listeners = [{
    name                  = "http"
    listener_port         = 80
    target_port           = 30080
    protocol              = "TCP"
    health_check_port     = 30080
    health_check_protocol = "TCP"
    health_check_path     = null
  }]
}

debug_retention_enabled = false
```

### Tagging Strategy

All resources receive tags via the AWS provider `default_tags` block plus resource-specific tags via `merge(var.tags, {...})`:

```hcl
locals {
  common_tags = {
    Project            = "KASBench"
    EnvironmentProfile = var.environment_profile
    RunId              = var.run_id
    ManagedBy          = "OpenTofu"
    Owner              = var.owner
    Purpose            = "KubernetesAutoscalingBenchmark"
    TrialId            = var.trial_id != null ? var.trial_id : ""
  }
}
```

The `default_tags` in the provider ensures every AWS resource gets the base tags without explicit per-resource configuration. Module-level `var.tags` passes additional context-specific tags.

## Error Handling

### Variable Validation

```hcl
variable "environment_profile" {
  validation {
    condition     = contains(["small", "benchmark"], var.environment_profile)
    error_message = "environment_profile must be 'small' or 'benchmark'."
  }
}

variable "availability_zone_mode" {
  validation {
    condition     = contains(["explicit", "random"], var.availability_zone_mode)
    error_message = "availability_zone_mode must be 'explicit' or 'random'."
  }
}

variable "availability_zone" {
  validation {
    condition     = var.availability_zone_mode == "random" || var.availability_zone != null
    error_message = "availability_zone is required when availability_zone_mode is 'explicit'."
  }
}

variable "worker_groups" {
  validation {
    condition     = var.worker_groups.amd64.count >= 1 && var.worker_groups.arm64.count >= 1
    error_message = "Each worker group must have at least 1 node."
  }
}
```

### Preconditions

```hcl
# In compute module — prevent debug retention in benchmark profile
resource "aws_instance" "control_plane" {
  # ...
  lifecycle {
    precondition {
      condition     = !(var.debug_retention_enabled && var.environment_profile == "benchmark")
      error_message = "debug_retention_enabled must be false for benchmark profile."
    }
  }
}
```

### Dependency Ordering

Module dependencies are expressed through input variable references. OpenTofu automatically determines the correct creation order. Explicit `depends_on` is avoided except for the NAT Gateway's dependency on the Internet Gateway (required for proper teardown ordering).

### Teardown Safety

- The stack only manages resources it creates. No `data` sources that could trigger modifications to external resources.
- The S3 bucket is referenced only by name in IAM policies — never as a managed resource.
- The bastion host is referenced only by its security group ID — never as a managed resource.
- `tofu destroy` removes all stack-managed resources in reverse dependency order.

## Testing Strategy

This project is Infrastructure as Code (IaC), which is declarative configuration rather than imperative logic with inputs/outputs. Property-based testing is not appropriate for IaC. The testing strategy uses:

### Plan Validation Tests

Verify that `tofu plan` produces expected resource types and configurations for each profile:

1. **Profile smoke tests**: `tofu plan -var-file=environments/small.tfvars` and `tofu plan -var-file=environments/benchmark.tfvars` both produce valid plans without errors
2. **Resource count verification**: Benchmark profile plans 12 EC2 instances (1 runner + 1 CP + 5 amd64 + 5 arm64); small profile plans 4 (1 + 1 + 1 + 1)
3. **Structural consistency**: Both profiles produce the same set of resource types (VPC, subnets, IGW, NAT GW, NLB, security groups, IAM roles)

### Policy/Compliance Checks

Use `tofu plan -out=plan.tfplan` with plan inspection or OPA/Conftest:

1. **Tag compliance**: All taggable resources include required tags
2. **SSH restriction**: All SSH ingress rules reference only the bastion security group
3. **NLB internality**: NLB `internal` attribute is always `true`
4. **No external resource management**: Plan never creates/modifies S3 buckets or bastion instances

### Integration Tests

Apply to a real AWS account and verify:

1. VPC and subnets are created in the correct AZ
2. Security group rules permit expected traffic paths
3. EC2 instances launch successfully with correct AMIs
4. NLB is reachable from benchmark-runner
5. Environment description files are generated with all required fields

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Note: This project is Infrastructure as Code (OpenTofu/HCL). IaC is declarative configuration, not imperative logic with varying inputs. The properties below are structural invariants best validated through plan inspection and policy checks (e.g., OPA/Conftest against `tofu show -json plan.tfplan`) rather than property-based testing with randomized inputs.

### Property 1: Tag Completeness

For any taggable AWS resource in the OpenTofu plan output, that resource SHALL contain all required tags: Project, EnvironmentProfile, RunId, ManagedBy, Owner, and Purpose.

**Validates: Requirements 17.1**

### Property 2: SSH Access Restriction

For any security group rule in the OpenTofu plan that permits ingress on port 22 (SSH), the source SHALL reference only the bastion host security group ID — never a CIDR block, "0.0.0.0/0", or any other security group.

**Validates: Requirements 6.5**

### Property 3: Environment Description Completeness

For any valid set of infrastructure inputs (any combination of profile, region, AZ, instance types, and node counts), the generated environment description JSON SHALL contain all required top-level fields: run_id, environment_profile, region, availability_zone, vpc_id, subnet_ids, security_groups, iam_roles, compute instances, nlb_metadata, ebs_volumes, and run_bucket_name.

**Validates: Requirements 16.3**

### Property 4: Profile Structural Equivalence

For any two valid profile configurations (small and benchmark), the set of OpenTofu resource types in the plan SHALL be identical — both profiles produce the same resource type set, differing only in count and sizing attributes.

**Validates: Requirements 1.5**

### Property 5: NLB Internality Invariant

For any configuration of the load-balancing module, the Network Load Balancer SHALL have `internal = true` and SHALL NOT expose any internet-facing endpoint.

**Validates: Requirements 11.3**

### Property 6: External Resource Immutability

For any OpenTofu plan produced by this stack, the plan SHALL NOT contain create, update, or delete actions targeting S3 bucket resources or EC2 instances tagged as bastion/controller hosts.

**Validates: Requirements 14.2, 15.2, 18.2**
