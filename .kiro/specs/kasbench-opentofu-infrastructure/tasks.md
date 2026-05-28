# Implementation Plan: KASBench OpenTofu Infrastructure

## Overview

Implement the KASBench AWS infrastructure as OpenTofu IaC with a root module at the repository root, seven child modules under `modules/`, and two environment profiles via tfvars files. Each task builds incrementally — starting with foundational files and the network module, then layering security, IAM, storage, compute, load balancing, and finally the environment description module that aggregates all outputs.

## Tasks

- [x] 1. Set up root module foundation and provider configuration
  - [x] 1.1 Create root module files: versions.tf, providers.tf, variables.tf
    - Create `versions.tf` with required OpenTofu version (>= 1.6.0) and required providers (aws ~> 5.0, random ~> 3.6, local ~> 2.5)
    - Create `providers.tf` with AWS provider configuration including `default_tags` block (Project, EnvironmentProfile, RunId, ManagedBy, Owner, Purpose)
    - Create `variables.tf` with all root-level input variables including validation blocks for `environment_profile`, `availability_zone_mode`, `availability_zone`, and `worker_groups`
    - Define `locals` block with `common_tags` map and computed `artifact_output_path`
    - _Requirements: 1.1, 1.4, 2.1, 17.1, 17.2, 17.3_

  - [x] 1.2 Create environment tfvars files
    - Create `environments/small.tfvars` with small profile defaults (t3.large CP, 1 worker per group, 50 GiB root volumes, explicit AZ)
    - Create `environments/benchmark.tfvars` with benchmark profile defaults (m8i.xlarge CP, 5 workers per group, 100 GiB root volumes, random AZ)
    - Include placeholder values for AMI IDs, bastion SG ID, and run bucket name
    - _Requirements: 1.2, 1.3, 1.4, 2.4_

  - [x] 1.3 Create directory structure and placeholder files
    - Create `modules/network/`, `modules/security/`, `modules/iam/`, `modules/compute/`, `modules/load-balancing/`, `modules/storage/`, `modules/environment-description/` directories
    - Create `artifacts/.gitkeep` for output directory
    - _Requirements: 2.2, 2.3_

- [x] 2. Implement Network Module
  - [x] 2.1 Create network module with VPC, subnets, and AZ selection
    - Create `modules/network/variables.tf` with inputs: vpc_cidr, public_subnet_cidr, private_subnet_cidr, availability_zone_mode, availability_zone, aws_region, tags
    - Create `modules/network/az.tf` with `data.aws_availability_zones`, `random_shuffle` resource (count-gated on mode), and `locals.selected_az`
    - Create `modules/network/main.tf` with VPC (dns_support, dns_hostnames enabled), public subnet, private subnet — all in `local.selected_az`
    - _Requirements: 3.1, 3.2, 3.3, 4.1, 4.2, 4.3_

  - [x] 2.2 Add Internet Gateway, NAT Gateway, and route tables
    - Add Internet Gateway attached to VPC
    - Add Elastic IP and NAT Gateway in public subnet with `depends_on` for IGW
    - Add public route table with 0.0.0.0/0 → IGW route and subnet association
    - Add private route table with 0.0.0.0/0 → NAT GW route and subnet association
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x] 2.3 Create network module outputs
    - Create `modules/network/outputs.tf` exposing: vpc_id, public_subnet_id, private_subnet_id, selected_availability_zone, igw_id, nat_gw_id, route_table_ids
    - _Requirements: 3.4, 4.4, 5.6_

- [x] 3. Implement Security Module
  - [x] 3.1 Create security module with all security groups and rules
    - Create `modules/security/variables.tf` with inputs: vpc_id, bastion_security_group_id, tags
    - Create `modules/security/main.tf` with four security groups: benchmark_runner, nlb, control_plane, worker_node
    - Implement benchmark-runner SG: SSH ingress from bastion only, all egress
    - Implement NLB SG: TCP ingress from benchmark-runner SG only
    - Implement control-plane SG: 6443 from workers + runner, 2379-2380 self, 10250 from workers, SSH from bastion, all egress
    - Implement worker-node SG: 10250 from CP, 30000-32767 self, 9090/9100 self (observability), SSH from bastion, all egress
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 7.4, 11.5, 21.1_

  - [x] 3.2 Create security module outputs
    - Create `modules/security/outputs.tf` exposing: benchmark_runner_sg_id, nlb_sg_id, control_plane_sg_id, worker_node_sg_id, all_security_groups (with rule descriptions)
    - _Requirements: 6.6_

- [x] 4. Implement IAM Module
  - [x] 4.1 Create IAM module with roles, policies, and instance profiles
    - Create `modules/iam/variables.tf` with inputs: run_bucket_name, environment_profile, tags
    - Create `modules/iam/main.tf` with EC2 assume-role policy document
    - Implement control-plane role: EC2 describe + EBS attach/detach scoped to KASBench tag
    - Implement worker-node role: EC2 describe + EBS CSI driver permissions (create/delete/attach volumes) + ECR read
    - Implement benchmark-runner role: S3 write scoped to specific run bucket ARN
    - Create instance profiles for all three roles
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 12.3, 15.3, 21.2_

  - [x] 4.2 Create IAM module outputs
    - Create `modules/iam/outputs.tf` exposing: control_plane_instance_profile_name, worker_instance_profile_name, benchmark_runner_instance_profile_name, all_roles
    - _Requirements: 13.5_

- [x] 5. Implement Storage Module
  - [x] 5.1 Create storage module with pre-created EBS volumes and StorageClass metadata
    - Create `modules/storage/variables.tf` with inputs: availability_zone, etcd_volume_config, environment_profile, debug_retention_enabled, tags
    - Create `modules/storage/main.tf` with pre-created GP3 EBS volume for etcd (configurable size, IOPS, throughput, encrypted)
    - Create `modules/storage/outputs.tf` exposing: etcd_volume_id, all_volumes (with metadata), storage_class_metadata (default_workload_storage, high_iops_storage)
    - _Requirements: 12.1, 12.2, 12.4, 21.4_

- [x] 6. Checkpoint - Validate foundational modules
  - Ensure all tests pass, ask the user if questions arise.
  - Run `tofu init` and `tofu validate` to confirm module structure is syntactically valid

- [x] 7. Implement Compute Module
  - [x] 7.1 Create compute module with benchmark-runner instance
    - Create `modules/compute/variables.tf` with all inputs: subnet IDs, AZ, configs, AMIs, SG IDs, profile names, etcd_volume_id, environment_profile, debug_retention_enabled, tags
    - Create `modules/compute/benchmark_runner.tf` with EC2 instance in public subnet, public IP, configurable root volume, role/architecture tags
    - _Requirements: 7.1, 7.2, 7.3, 7.5, 10.2_

  - [x] 7.2 Create compute module with control-plane instance and etcd volume attachment
    - Create `modules/compute/control_plane.tf` with EC2 instance in private subnet, configurable instance type, role metadata tags (kubernetes-role=control-plane, kubernetes-arch=amd64)
    - Add `aws_volume_attachment` for etcd EBS volume
    - Add lifecycle precondition to prevent debug_retention_enabled in benchmark profile
    - _Requirements: 8.1, 8.2, 8.3, 12.5, 22.2, 22.3_

  - [x] 7.3 Create compute module with worker node groups
    - Create `modules/compute/workers.tf` with amd64 worker group using `count` and arm64 worker group using `count`
    - Apply architecture-specific AMIs, tags (kubernetes-arch, node-group, node-index), and configurable root volumes
    - _Requirements: 9.1, 9.2, 9.3, 9.5, 10.2, 12.5_

  - [x] 7.4 Create compute module outputs
    - Create `modules/compute/outputs.tf` exposing: control_plane_metadata, worker_nodes_metadata (grouped by arch with per-node details), benchmark_runner_metadata
    - _Requirements: 8.3, 9.4, 19.1, 19.2_

- [ ] 8. Implement Load Balancing Module
  - [~] 8.1 Create load-balancing module with internal NLB, listeners, and target groups
    - Create `modules/load-balancing/variables.tf` with inputs: vpc_id, private_subnet_id, nlb_sg_id, nlb_config, tags
    - Create `modules/load-balancing/main.tf` with internal NLB (internal=true, network type), target groups with configurable health checks, listeners with for_each over nlb_config.listeners
    - Create `modules/load-balancing/outputs.tf` exposing: nlb_metadata (dns_name, arn, scheme, listeners, target_groups)
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 19.4_

- [ ] 9. Implement Environment Description Module
  - [~] 9.1 Create environment-description module variables and structure
    - Create `modules/environment-description/variables.tf` with all inputs (run_id, profile, region, AZ, network outputs, security outputs, IAM outputs, compute outputs, NLB outputs, storage outputs, external refs, metadata)
    - Create `modules/environment-description/templates/` directory
    - _Requirements: 16.1, 16.2_

  - [~] 9.2 Create JSON template and local_file resource
    - Create `modules/environment-description/templates/environment-description.json.tftpl` with full infrastructure metadata structure
    - Include: metadata (run_id, profile, timestamps, versions), infrastructure (network, security, IAM, compute, NLB, storage), external dependencies, kubernetes/observability/autoscaler metadata
    - Handle optional metadata fields with conditional inclusion (omit or mark "not provided")
    - _Requirements: 16.1, 16.3, 16.5, 20.2, 20.3, 23.4_

  - [~] 9.3 Create Markdown template and local_file resource
    - Create `modules/environment-description/templates/environment-description.md.tftpl` with human-readable report format
    - Include all the same data as JSON but formatted as Markdown tables and sections
    - _Requirements: 16.2, 16.3_

  - [~] 9.4 Create environment-description module main.tf and outputs
    - Create `modules/environment-description/main.tf` with templatefile() calls, local_file resources for JSON, Markdown, and checksums
    - Create `modules/environment-description/outputs.tf` exposing: json_path, markdown_path, checksums_path
    - _Requirements: 16.4, 23.5_

- [~] 10. Checkpoint - Validate all modules independently
  - Ensure all tests pass, ask the user if questions arise.
  - Run `tofu validate` to confirm all modules parse correctly

- [ ] 11. Wire modules together in root main.tf and outputs.tf
  - [~] 11.1 Create root main.tf with all module instantiations
    - Instantiate all 7 modules with correct variable passing and cross-module output references
    - Follow dependency order: network → security, iam, storage → compute → load-balancing → environment-description
    - Pass common_tags to all modules
    - Compute artifact_output_path as `artifacts/${var.run_id}/` when not explicitly set
    - _Requirements: 2.1, 2.5, 14.1, 14.3, 15.1, 19.5, 19.6, 20.1_

  - [~] 11.2 Create root outputs.tf with bootstrap handoff outputs
    - Expose: control_plane, worker_nodes, benchmark_runner, nlb, security_groups, storage, network, run_bucket_name, run_id, environment_description_paths
    - Include AMI IDs used for reproducibility auditing
    - _Requirements: 10.3, 18.3, 19.1, 19.2, 19.3, 19.4, 19.5, 19.6, 23.1, 23.2, 23.3_

- [ ] 12. Implement debug retention and operational features
  - [~] 12.1 Add debug retention logic to compute and storage modules
    - Add lifecycle preconditions that error on `tofu destroy` when debug_retention_enabled=true and profile=small
    - Ensure benchmark profile always ignores debug_retention_enabled
    - Add `debug_retention_enabled` variable acceptance in relevant modules
    - _Requirements: 22.1, 22.2, 22.3_

- [ ] 13. Final validation and plan testing
  - [ ]* 13.1 Validate plan with small profile
    - Run `tofu init` and `tofu plan -var-file=environments/small.tfvars` (with placeholder values filled)
    - Verify plan produces expected resource count (4 EC2 instances, 1 VPC, 2 subnets, 1 IGW, 1 NAT GW, 4 SGs, 1 NLB, 1 EBS volume)
    - _Requirements: 1.2, 1.5_

  - [ ]* 13.2 Validate plan with benchmark profile
    - Run `tofu plan -var-file=environments/benchmark.tfvars` (with placeholder values filled)
    - Verify plan produces expected resource count (12 EC2 instances, same structural resources as small)
    - _Requirements: 1.3, 1.5_

  - [ ]* 13.3 Verify structural invariants via plan inspection
    - Confirm all SSH rules reference bastion SG only (Property 2)
    - Confirm NLB has internal=true (Property 5)
    - Confirm no S3 bucket or bastion resources in plan (Property 6)
    - Confirm all taggable resources include required tags (Property 1)
    - _Requirements: 6.5, 11.3, 14.2, 15.2, 17.1, 18.2_

- [~] 14. Final checkpoint - Ensure all validation passes
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation via `tofu init` and `tofu validate`
- The design uses HCL throughout — no language selection needed
- This is IaC (declarative configuration), so testing uses plan validation and policy checks rather than property-based testing
- Debug retention uses lifecycle preconditions since HCL does not support dynamic lifecycle blocks
- Placeholder values (AMI IDs, bastion SG, bucket names) must be replaced with real values before plan validation succeeds

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.3"] },
    { "id": 1, "tasks": ["1.2", "2.1"] },
    { "id": 2, "tasks": ["2.2", "2.3"] },
    { "id": 3, "tasks": ["3.1", "4.1", "5.1"] },
    { "id": 4, "tasks": ["3.2", "4.2"] },
    { "id": 5, "tasks": ["7.1", "8.1"] },
    { "id": 6, "tasks": ["7.2", "7.3"] },
    { "id": 7, "tasks": ["7.4"] },
    { "id": 8, "tasks": ["9.1"] },
    { "id": 9, "tasks": ["9.2", "9.3"] },
    { "id": 10, "tasks": ["9.4"] },
    { "id": 11, "tasks": ["11.1"] },
    { "id": 12, "tasks": ["11.2", "12.1"] },
    { "id": 13, "tasks": ["13.1", "13.2", "13.3"] }
  ]
}
```
