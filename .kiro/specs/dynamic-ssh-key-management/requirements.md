# Requirements Document

## Introduction

This feature replaces the existing static SSH key pair reference (`key_name` variable pointing to a pre-existing EC2 key pair) with a dynamically generated ED25519 key pair managed entirely by OpenTofu. The generated key is registered with AWS EC2, saved locally for runner access, and injected into all fleet instances via cloud-init to enable SSH agent forwarding for intra-fleet communication. This eliminates the manual prerequisite of creating an EC2 key pair before provisioning infrastructure.

## Glossary

- **Key_Generator**: The OpenTofu `tls_private_key` resource that produces an ED25519 key pair at plan/apply time
- **Key_Registrar**: The OpenTofu `aws_key_pair` resource that registers the generated public key with AWS EC2
- **Key_Writer**: The OpenTofu `local_sensitive_file` resource that persists the private key to the local filesystem
- **Fleet_Instance**: Any EC2 instance in the KASBench infrastructure (benchmark runner, control plane, or worker node)
- **Cloud_Init_Configurator**: The `user_data` script applied to Fleet_Instances that configures SSH daemon settings
- **Agent_Forwarding**: SSH protocol feature that allows a connected client's authentication agent to be used on the remote host for onward connections
- **Root_Module**: The top-level OpenTofu configuration at the repository root
- **Compute_Module**: The child module at `modules/compute` responsible for EC2 instance creation

## Requirements

### Requirement 1: ED25519 Key Pair Generation

**User Story:** As an infrastructure operator, I want OpenTofu to generate a fresh SSH key pair on each deployment, so that I do not need to manually create or manage EC2 key pairs as a prerequisite.

#### Acceptance Criteria

1. THE Key_Generator SHALL produce an ED25519 key pair using the `tls_private_key` resource with algorithm set to "ED25519"
2. WHEN OpenTofu applies the configuration, THE Key_Generator SHALL produce a public key in OpenSSH format beginning with the "ssh-ed25519" prefix
3. WHEN OpenTofu applies the configuration, THE Key_Generator SHALL produce a private key in PEM format containing valid PEM header and footer markers and a non-empty key body
4. WHEN OpenTofu destroys and re-applies the configuration, THE Key_Generator SHALL produce a new key pair distinct from any previously generated pair
5. THE Key_Generator SHALL mark the private key output as sensitive so that OpenTofu redacts it from CLI output and plan displays

### Requirement 2: AWS EC2 Key Pair Registration

**User Story:** As an infrastructure operator, I want the generated public key registered with AWS EC2, so that instances can be launched with the dynamically created key pair.

#### Acceptance Criteria

1. THE Key_Registrar SHALL register the generated public key with AWS EC2 using the `aws_key_pair` resource
2. THE Key_Registrar SHALL use the public key output from the Key_Generator as its `public_key` attribute
3. THE Key_Registrar SHALL assign a key pair name using the format `kasbench-<run_id>` where `<run_id>` is the value of the `run_id` variable, producing a name no longer than 255 characters
4. IF an `aws_key_pair` resource with the same name already exists in the target AWS account and region, THEN THE Key_Registrar SHALL fail the OpenTofu apply with an error indicating a key pair name conflict

### Requirement 3: Local Private Key Persistence

**User Story:** As an infrastructure operator, I want the generated private key saved locally with restrictive permissions, so that I can use it to SSH into fleet instances from the runner machine.

#### Acceptance Criteria

1. THE Key_Writer SHALL save the Key_Generator `private_key_pem` output to a local file using the `local_sensitive_file` resource with the `content` attribute set to the Key_Generator private key PEM value
2. THE Key_Writer SHALL set file permissions to "0600" on the saved private key file using the `file_permission` attribute
3. THE Key_Writer SHALL write the file to the path `"${local.artifact_output_path}fleet_key.pem"` so that the private key is located within the run-specific artifacts directory with a fixed filename
4. IF the artifacts output directory does not exist at apply time, THEN THE Key_Writer SHALL create intermediate directories as needed to write the private key file

### Requirement 4: Fleet Instance Key Assignment

**User Story:** As an infrastructure operator, I want all EC2 instances to use the dynamically generated key pair, so that SSH access is consistent across the entire fleet.

#### Acceptance Criteria

1. THE Compute_Module SHALL accept the generated key pair name as a required input variable of type string with no default value
2. WHEN a Fleet_Instance is created, THE Compute_Module SHALL assign the key pair name variable to the `key_name` attribute of every EC2 instance resource (benchmark runner, control plane, and all worker nodes)
3. THE Root_Module SHALL pass the Key_Registrar key pair name output to the Compute_Module's key pair name variable
4. IF the key pair name input variable is an empty string, THEN THE Compute_Module SHALL fail validation with an error message indicating that a non-empty key pair name is required

### Requirement 5: SSH Agent Forwarding Configuration

**User Story:** As an infrastructure operator, I want all fleet instances to allow SSH agent forwarding, so that I can hop between hosts without distributing private keys to instances.

#### Acceptance Criteria

1. WHEN a Fleet_Instance is launched, THE Cloud_Init_Configurator SHALL configure the SSH daemon to allow agent forwarding by appending "AllowAgentForwarding yes" to `/etc/ssh/sshd_config`
2. WHEN the Cloud_Init_Configurator has appended the AllowAgentForwarding directive, THE Cloud_Init_Configurator SHALL restart the SSH service using `systemctl restart ssh` to apply the change
3. IF the SSH service fails to restart after configuration, THEN THE Cloud_Init_Configurator SHALL exit with a non-zero status code indicating the failure

### Requirement 6: Public Key Injection via Cloud-Init

**User Story:** As an infrastructure operator, I want the generated public key injected into all instances via cloud-init, so that fleet hosts natively trust the key for direct intra-fleet SSH communication as a fallback.

#### Acceptance Criteria

1. WHEN a Fleet_Instance is launched, THE Cloud_Init_Configurator SHALL append the generated public key to the authorized_keys file for the default user without removing any existing entries
2. THE Compute_Module SHALL accept the generated public key value as an input variable passed from the Root_Module
3. THE Cloud_Init_Configurator SHALL use the public key value received from the Compute_Module input variable to construct the authorized_keys entry
4. WHEN a Fleet_Instance is launched, THE Cloud_Init_Configurator SHALL apply the public key injection to every Fleet_Instance type (benchmark runner, control plane, and worker nodes)

### Requirement 7: Provider Configuration Update

**User Story:** As an infrastructure operator, I want the `tls` provider declared in the OpenTofu configuration, so that the `tls_private_key` resource is available for key generation.

#### Acceptance Criteria

1. THE Root_Module SHALL declare the `tls` provider in the `required_providers` block in `versions.tf` with `source` set to "hashicorp/tls"
2. THE Root_Module SHALL pin the `tls` provider version constraint to "~> 4.0"
3. WHEN `tofu init` is executed, THE Root_Module SHALL successfully resolve and download the `tls` provider without errors

### Requirement 8: Legacy Key Variable Removal

**User Story:** As an infrastructure operator, I want the static `key_name` variable removed from the configuration, so that there is no confusion between the old manual approach and the new dynamic approach.

#### Acceptance Criteria

1. THE Root_Module SHALL remove the `key_name` variable from `variables.tf`
2. THE Root_Module SHALL remove the `key_name = var.key_name` argument from the compute module invocation in `main.tf`
3. THE Compute_Module SHALL remove the `key_name` variable from its `variables.tf`
4. THE Compute_Module SHALL remove the `key_name = var.key_name` argument from all EC2 instance resource blocks (`benchmark_runner.tf`, `control_plane.tf`, `workers.tf`)
5. IF any `.tfvars` file references `key_name`, THEN THE Root_Module SHALL remove that reference
6. WHEN all `key_name` references have been removed, THE Root_Module SHALL pass `tofu validate` without errors related to undefined variables or missing arguments

### Requirement 9: Output of SSH Connection Details

**User Story:** As an infrastructure operator, I want the SSH private key path and key pair name exposed as outputs, so that automation scripts and operators can easily locate the credentials needed to connect.

#### Acceptance Criteria

1. THE Root_Module SHALL output the local file path of the saved private key as a string-type output named "ssh_private_key_path" with the value matching the file path written by the Key_Writer
2. THE Root_Module SHALL mark the "ssh_private_key_path" output as sensitive
3. THE Root_Module SHALL output the AWS EC2 key pair name assigned to fleet instances as a string-type output named "ssh_key_pair_name" with the value matching the key pair name registered by the Key_Registrar
