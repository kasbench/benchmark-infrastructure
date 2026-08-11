# KASBench Benchmark Infrastructure

OpenTofu infrastructure-as-code for provisioning the KASBench (Kubernetes Autoscaler Benchmark) AWS environment. This stack deploys a self-managed Kubernetes cluster on EC2 with heterogeneous worker nodes, a public NLB for benchmark traffic routing, and full environment description generation for reproducibility.

## Architecture Overview

All instances reside in a single public subnet and use the Internet Gateway directly for outbound access (container image pulls, etc.). There is no NAT Gateway — this keeps costs low for a short-lived benchmark environment with only synthetic data.

```
┌─────────────────────────────────────────────────────────────────────┐
│                      KASBench VPC (10.0.0.0/16)                     │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                   Public Subnet (10.0.1.0/24)                 │  │
│  │                                                               │  │
│  │  ┌──────────────────┐  ┌────────────────────────────────────┐ │  │
│  │  │ Benchmark Runner │  │ Control Plane (amd64)              │ │  │
│  │  │ (t3.medium)      │  │ + etcd EBS volume                  │ │  │
│  │  └──────────────────┘  └────────────────────────────────────┘ │  │
│  │                                                               │  │
│  │  ┌────────────────────────────────────────────────────────┐   │  │
│  │  │ Workers: amd64 group + arm64 group                     │   │  │
│  │  └────────────────────────────────────────────────────────┘   │  │
│  │                                                               │  │
│  │  ┌──────────────────┐  ┌────────────────────────────────────┐ │  │
│  │  │ Internet Gateway │  │ Public NLB → Workers :30080        │ │  │
│  │  └──────────────────┘  └────────────────────────────────────┘ │  │
│  │                                                               │  │
│  └───────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────┬────────────────────────────────┘
                                     │ VPC Peering
┌────────────────────────────────────┴────────────────────────────────┐
│                     Bastion VPC (172.31.0.0/16)                     │
│                                                                     │
│  ┌─────────────┐                                                    │
│  │ Bastion Host│  (externally managed, 172.31.23.100)               │
│  └─────────────┘                                                    │
└─────────────────────────────────────────────────────────────────────┘
```


## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6.0
- AWS credentials configured (via environment variables, `~/.aws/credentials`, or IAM role)
- A pre-existing **bastion host** with a known private IP (in a separate VPC)
- A pre-existing **S3 bucket** for benchmark run artifacts
- Custom **AMI IDs** for amd64 and arm64 instances (pre-built with Kubernetes toolchain)

## Repository Structure

```
.
├── main.tf                     # Root module — wires all child modules together
├── variables.tf                # All root-level input variables
├── outputs.tf                  # Outputs for Kubernetes bootstrap handoff
├── providers.tf                # AWS provider with default tags
├── versions.tf                 # OpenTofu and provider version constraints
├── environments/
│   ├── small.tfvars            # Small profile (dev/iteration)
│   └── benchmark.tfvars       # Full benchmark profile
├── modules/
│   ├── network/                # VPC, subnet, IGW, route tables, AZ selection, VPC peering
│   ├── security/               # Security groups and rules
│   ├── iam/                    # IAM roles, policies, instance profiles
│   ├── compute/                # EC2 instances (CP, workers, benchmark-runner)
│   ├── load-balancing/         # Public NLB, listeners, target groups
│   ├── storage/                # Pre-created EBS volumes, StorageClass metadata
│   └── environment-description/ # JSON + Markdown report generation
└── artifacts/                  # Generated environment description output
```

## Environment Profiles

| Parameter | Small | Benchmark |
|-----------|-------|-----------|
| Control Plane | t3.large | m8i.xlarge |
| Workers per group | 1 | 5 |
| Worker types (amd64) | t3.large | c8i.4xlarge |
| Worker types (arm64) | t4g.large | c8g.4xlarge |
| Root volume | 50 GiB GP3 | 100 GiB GP3 |
| etcd volume | 20 GiB GP3 | 50 GiB GP3 |
| AZ selection | Explicit | Random |
| Total EC2 instances | 4 | 12 |

## Quick Start

### 1. Initialize

```bash
tofu init
```

### 2. Configure Variables

Copy and edit the appropriate tfvars file. You **must** replace all `PLACEHOLDER` values:

```bash
cp environments/small.tfvars environments/my-run.tfvars
```

Required replacements:

| Variable | Description |
|----------|-------------|
| `run_id` | Unique identifier for this benchmark run (e.g., `run-2026-05-28-001`) |
| `owner` | Your name or team for cost allocation tags |
| `bastion_ssh_cidr` | Private IP of your bastion host as a /32 CIDR (e.g., `"172.31.23.100/32"`) |
| `bastion_vpc_id` | VPC ID where the bastion host resides (for VPC peering) |
| `bastion_vpc_cidr` | CIDR block of the bastion VPC (for route table entries) |
| `run_bucket_name` | Name of the pre-existing S3 bucket for artifacts |
| `ami_amd64` | AMI ID for amd64 instances |
| `ami_arm64` | AMI ID for arm64 instances |

### 3. Plan

Preview what will be created:

```bash
# Small profile (development)
tofu plan -var-file=environments/small.tfvars

# Benchmark profile (full scale)
tofu plan -var-file=environments/benchmark.tfvars
```

### 4. Apply

Provision the infrastructure:

```bash
tofu apply -var-file=environments/small.tfvars
```

### 5. Retrieve Outputs

After apply, get the bootstrap handoff data:

```bash
# All outputs as JSON
tofu output -json

# Specific outputs
tofu output control_plane
tofu output worker_nodes
tofu output nlb
```

### 6. Destroy

Tear down all stack-managed resources:

```bash
tofu destroy -var-file=environments/small.tfvars
```

This destroys all resources created by the stack (VPC, EC2, EBS, NLB, IAM, security groups) but does **not** affect the bastion host, S3 bucket, or AMIs.

## Key Variables

### Required

| Variable | Type | Description |
|----------|------|-------------|
| `environment_profile` | `string` | `"small"` or `"benchmark"` |
| `availability_zone_mode` | `string` | `"explicit"` or `"random"` |
| `run_id` | `string` | Unique benchmark run identifier |
| `owner` | `string` | Owner for cost allocation |
| `bastion_ssh_cidr` | `string` | Bastion host private IP as /32 CIDR |
| `bastion_vpc_id` | `string` | Bastion VPC ID (for VPC peering) |
| `bastion_vpc_cidr` | `string` | Bastion VPC CIDR (for routing) |
| `run_bucket_name` | `string` | Pre-existing S3 bucket name |
| `ami_amd64` | `string` | AMI ID for amd64 instances |
| `ami_arm64` | `string` | AMI ID for arm64 instances |

### Optional

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `availability_zone` | `string` | `null` | Explicit AZ (required when mode is `"explicit"`) |
| `debug_retention_enabled` | `bool` | `false` | Prevent destroy in small profile for debugging |
| `kubernetes_metadata` | `object` | `null` | K8s version, CNI, runtime metadata for reports |
| `observability_metadata` | `object` | `null` | Prometheus/Jaeger retention metadata |
| `autoscaler_metadata` | `object` | `null` | Autoscaler config metadata |
| `nlb_config` | `object` | HTTP on port 80→30080 | NLB listener/target group configuration |
| `trial_id` | `string` | `null` | Optional trial ID for tagging |

## Outputs

The stack exposes outputs designed for the separate Kubernetes bootstrap process:

- **`control_plane`** — Instance ID, private IP, type, AMI, architecture
- **`worker_nodes`** — Per-node metadata grouped by architecture
- **`benchmark_runner`** — Instance ID, public/private IPs
- **`nlb`** — DNS name, ARN, listener and target group details
- **`security_groups`** — All SG IDs with rule descriptions
- **`storage`** — EBS volume IDs and StorageClass metadata
- **`network`** — VPC ID, subnet ID, AZ, gateway ID
- **`environment_description_paths`** — Paths to generated JSON/Markdown reports
- **`provisioning_metadata`** — OpenTofu version, timestamp, git commit hash

## Example Output

After a successful `tofu apply`, `tofu output -json` produces output similar to:

```json
{
  "control_plane": {
    "value": {
      "instance_id": "i-0a1b2c3d4e5f67890",
      "private_ip": "10.0.1.50",
      "instance_type": "t3.large",
      "ami_id": "ami-0abc123def456789a",
      "architecture": "amd64"
    }
  },
  "worker_nodes": {
    "value": {
      "amd64": [
        {
          "instance_id": "i-0amd64worker00001",
          "private_ip": "10.0.1.101",
          "instance_type": "t3.large",
          "ami_id": "ami-0abc123def456789a",
          "architecture": "amd64"
        }
      ],
      "arm64": [
        {
          "instance_id": "i-0arm64worker00001",
          "private_ip": "10.0.1.201",
          "instance_type": "t4g.large",
          "ami_id": "ami-0def456789abc1230",
          "architecture": "arm64"
        }
      ]
    }
  },
  "benchmark_runner": {
    "value": {
      "instance_id": "i-0bench1a2b3c4d5e6",
      "public_ip": "54.123.45.67",
      "private_ip": "10.0.0.50"
    }
  },
  "nlb": {
    "value": {
      "dns_name": "kasbench-nlb-run-2026-05-28-001-abc123.elb.us-east-1.amazonaws.com",
      "arn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/kasbench-nlb-run-2026-05-28-001/abc123def456",
      "listener_arn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/net/kasbench-nlb-run-2026-05-28-001/abc123def456/789ghi",
      "target_group_arn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/kasbench-tg-run-2026-05-28-001/xyz789abc123"
    }
  },
  "security_groups": {
    "value": {
      "control_plane_sg": {
        "id": "sg-0cp1234567890abcd",
        "rules": ["Allow SSH from bastion", "Allow K8s API (6443) from VPC", "Allow kubelet from workers"]
      },
      "worker_sg": {
        "id": "sg-0wk1234567890abcd",
        "rules": ["Allow SSH from bastion", "Allow all from control plane", "Allow NodePort range from NLB"]
      },
      "benchmark_runner_sg": {
        "id": "sg-0br1234567890abcd",
        "rules": ["Allow SSH from bastion", "Allow egress to VPC"]
      },
      "nlb_sg": {
        "id": "sg-0nlb234567890abcd",
        "rules": ["Allow HTTP (80) from VPC"]
      }
    }
  },
  "storage": {
    "value": {
      "ebs_volumes": {
        "etcd": {
          "volume_id": "vol-0etcd1234567890ab",
          "size_gb": 20,
          "type": "gp3",
          "availability_zone": "us-east-1a"
        }
      },
      "storage_class_metadata": {
        "provisioner": "ebs.csi.aws.com",
        "type": "gp3",
        "fs_type": "ext4"
      }
    }
  },
  "network": {
    "value": {
      "vpc_id": "vpc-0kasbench1234abcd",
      "public_subnet_id": "subnet-0pub1234567890abc",
      "selected_availability_zone": "us-east-1a",
      "igw_id": "igw-0kas1234567890abc",
      "route_table_ids": {
        "public": "rtb-0pub1234567890abc"
      }
    }
  },
  "run_bucket_name": {
    "value": "kasbench-runs-2026"
  },
  "run_id": {
    "value": "run-2026-05-28-001"
  },
  "environment_description_paths": {
    "value": {
      "json_path": "artifacts/run-2026-05-28-001/environment-description.json",
      "markdown_path": "artifacts/run-2026-05-28-001/environment-description.md",
      "checksums_path": "artifacts/run-2026-05-28-001/checksums.txt"
    }
  },
  "ami_ids": {
    "value": {
      "amd64": "ami-0abc123def456789a",
      "arm64": "ami-0def456789abc1230"
    }
  },
  "provisioning_metadata": {
    "value": {
      "opentofu_version": ">=1.6.0 (constraint)",
      "creation_timestamp": "2026-05-28T14:32:07Z",
      "git_commit_hash": "a3f8c2d1e4b5678901234567890abcdef1234567"
    }
  },
  "ssh_key_pair_name": {
    "value": "kasbench-fleet-run-2026-05-28-001"
  },
  "environment_profile": {
    "value": "small"
  }
}
```

> **Note:** `ssh_private_key_path` is marked `sensitive` and is redacted from JSON output. Use `tofu output ssh_private_key_path` to retrieve it directly.

## Environment Description

After `tofu apply`, the stack generates environment description files in `artifacts/<run_id>/`:

- **`environment-description.json`** — Machine-readable full infrastructure record
- **`environment-description.md`** — Human-readable Markdown report
- **`checksums.txt`** — SHA256 checksums of generated files

These files capture everything needed for the Full Disclosure Report: instance types, AMIs, network topology, security rules, IAM roles, storage config, and all metadata.

## Debug Retention Mode

For iterative development with the small profile, enable debug retention to prevent accidental `tofu destroy`:

```bash
tofu apply -var-file=environments/small.tfvars -var="debug_retention_enabled=true"
```

This adds lifecycle preconditions that block destruction of EC2 instances and EBS volumes. The benchmark profile always ignores this flag.

## Security Model

This is a short-lived benchmark environment running only synthetic data. The network topology prioritizes simplicity and cost over defense-in-depth, while remaining reasonably tamper-proof:

- All instances have public IPs but are protected by restrictive security groups
- SSH access is restricted to the bastion host's private IP via CIDR-based security group rules
- VPC peering connects the bastion VPC to the KASBench VPC with routes in both directions
- The Kubernetes API (port 6443) is only accessible from within the VPC (workers, runner)
- The NLB is internet-facing to allow the benchmark runner to route traffic to worker NodePorts
- IAM roles follow least-privilege (scoped to specific resources/tags)
- Worker nodes get EBS CSI permissions for dynamic volume provisioning
- Benchmark runner gets S3 write access scoped to the specific run bucket
- No NAT Gateway — all outbound traffic goes directly through the Internet Gateway

## Providers

| Provider | Source | Version |
|----------|--------|---------|
| AWS | `opentofu/aws` | `~> 5.0` |
| Random | `hashicorp/random` | `~> 3.6` |
| Local | `hashicorp/local` | `~> 2.5` |

## External Dependencies

This stack **does not manage** the following resources — they must exist before apply:

1. **Bastion Host** — EC2 instance in a separate VPC with a known private IP. This stack creates a VPC peering connection and bidirectional routes automatically.
2. **S3 Run Bucket** — Pre-created bucket for benchmark artifacts
3. **AMIs** — Custom machine images with Kubernetes toolchain pre-installed

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
