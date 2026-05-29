# Implementation Plan: Dynamic SSH Key Management

## Overview

Replace the static `key_name` variable (referencing a pre-existing EC2 key pair) with a fully OpenTofu-managed SSH key lifecycle. The implementation adds the `tls` provider, generates an ED25519 key pair at apply time, registers it with AWS EC2, persists the private key locally, and configures all fleet instances via cloud-init for SSH agent forwarding and public key injection.

## Tasks

- [x] 1. Add TLS provider and create key generation resources
  - [x] 1.1 Add the `tls` provider to `versions.tf`
    - Add `tls = { source = "hashicorp/tls", version = "~> 4.0" }` to the `required_providers` block
    - _Requirements: 7.1, 7.2, 7.3_

  - [x] 1.2 Create `ssh_key.tf` in the repository root with key generation, registration, and persistence resources
    - Add `tls_private_key.fleet_key` resource with `algorithm = "ED25519"`
    - Add `aws_key_pair.fleet_key` resource with `key_name = "kasbench-${var.run_id}"` and `public_key = tls_private_key.fleet_key.public_key_openssh`
    - Add `local_sensitive_file.fleet_private_key` resource with `content = tls_private_key.fleet_key.private_key_pem`, `filename = "${local.artifact_output_path}fleet_key.pem"`, and `file_permission = "0600"`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4_

- [x] 2. Update compute module interface and add cloud-init
  - [x] 2.1 Update `modules/compute/variables.tf` — add validation to `key_name` and add `fleet_public_key` variable
    - Replace the existing `key_name` variable block with one that includes a `validation` block: `condition = length(var.key_name) > 0`, `error_message = "A non-empty key pair name is required."`
    - Add new variable `fleet_public_key` of type `string` with description "SSH public key (OpenSSH format) to inject into all fleet instances via cloud-init"
    - _Requirements: 4.1, 4.4, 6.2_

  - [x] 2.2 Create `modules/compute/user_data.tf` with the cloud-init locals block
    - Define `locals { cloud_init_script = <<-EOF ... EOF }` containing a bash script that:
      - Uses `set -euo pipefail` for strict error handling
      - Appends `var.fleet_public_key` to `/home/ubuntu/.ssh/authorized_keys` (creating dir if needed, setting 600 perms, chown ubuntu:ubuntu)
      - Appends `AllowAgentForwarding yes` to `/etc/ssh/sshd_config`
      - Runs `systemctl restart ssh`
    - _Requirements: 5.1, 5.2, 5.3, 6.1, 6.3, 6.4_

  - [x] 2.3 Add `user_data` attribute to all EC2 instance resources
    - In `modules/compute/benchmark_runner.tf`: add `user_data = local.cloud_init_script` to `aws_instance.benchmark_runner`
    - In `modules/compute/control_plane.tf`: add `user_data = local.cloud_init_script` to `aws_instance.control_plane`
    - In `modules/compute/workers.tf`: add `user_data = local.cloud_init_script` to both `aws_instance.worker_amd64` and `aws_instance.worker_arm64`
    - _Requirements: 5.1, 6.4_

- [x] 3. Checkpoint - Validate compute module changes
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Wire root module and remove legacy variable
  - [x] 4.1 Update `main.tf` — replace static key_name with dynamic references in the compute module call
    - Replace `key_name = var.key_name` with `key_name = aws_key_pair.fleet_key.key_name`
    - Add `fleet_public_key = tls_private_key.fleet_key.public_key_openssh` to the compute module invocation
    - _Requirements: 4.3, 6.2, 6.3_

  - [x] 4.2 Remove the `key_name` variable from root `variables.tf`
    - Delete the entire `key_name` variable block (including the "SSH Key Pair" section header comment)
    - _Requirements: 8.1_

  - [x] 4.3 Add SSH outputs to root `outputs.tf`
    - Add `output "ssh_private_key_path"` with `value = local_sensitive_file.fleet_private_key.filename`, `sensitive = true`
    - Add `output "ssh_key_pair_name"` with `value = aws_key_pair.fleet_key.key_name`
    - _Requirements: 9.1, 9.2, 9.3_

- [x] 5. Final checkpoint - Run `tofu validate` and confirm no legacy references
  - Run `tofu validate` to confirm no undefined variable errors or missing arguments
  - Verify no `.tfvars` files reference `key_name` (grep check)
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 8.5, 8.6_

## Notes

- No property-based tests are included because this feature is purely IaC (declarative resource configuration) with no pure functions or business logic to exercise across input spaces
- Validation is done via `tofu validate` and `tofu plan` as described in the design's testing strategy
- The `key_name` variable in the compute module is kept but updated with validation — it's still needed as an input from the root module
- The `local_sensitive_file` resource handles intermediate directory creation automatically
- No `.tfvars` files currently reference `key_name`, so Requirement 8.5 is already satisfied

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1"] },
    { "id": 2, "tasks": ["2.2"] },
    { "id": 3, "tasks": ["2.3"] },
    { "id": 4, "tasks": ["4.1", "4.2", "4.3"] }
  ]
}
```
