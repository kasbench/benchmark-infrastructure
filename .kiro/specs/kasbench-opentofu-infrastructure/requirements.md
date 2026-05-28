# Requirements Document

## Introduction

This document specifies the requirements for implementing the KASBench AWS infrastructure as OpenTofu infrastructure-as-code. The infrastructure supports a self-managed Kubernetes cluster on AWS for evaluating Kubernetes autoscalers as part of a dissertation benchmark. Two environment profiles ("small" and "benchmark") are switchable via tfvars files without modifying core module logic. The OpenTofu root module resides at the repository root with modules in `modules/` and environment configurations in `environments/`.

## Glossary

- **OpenTofu_Stack**: The complete set of OpenTofu configuration files at the repository root that provisions and manages the KASBench AWS infrastructure
- **VPC**: An isolated AWS Virtual Private Cloud network created by the OpenTofu_Stack
- **Control_Plane_Node**: A single EC2 instance in the private subnet running the Kubernetes control-plane components
- **Worker_Node**: An EC2 instance in the private subnet that runs Kubernetes workload pods
- **Benchmark_Runner**: A single EC2 instance in the public subnet that executes benchmark traffic generation against the internal NLB
- **Bastion_Host**: An externally managed EC2 instance outside the OpenTofu_Stack used for SSH access and benchmark orchestration
- **Internal_NLB**: An internal AWS Network Load Balancer that routes benchmark traffic to the Kubernetes Gateway API or ingress controller
- **Environment_Profile**: A named configuration set (either "small" or "benchmark") that determines instance types, node counts, and volume sizes
- **Run_Bucket**: A pre-existing S3 bucket created outside the OpenTofu_Stack, used to store all artifacts for a single benchmark run
- **Environment_Description_Module**: The OpenTofu module that renders JSON and Markdown environment reports using templatefile() and local_file resources
- **EBS_CSI_Driver**: The AWS EBS Container Storage Interface driver that dynamically provisions Kubernetes persistent volumes
- **Network_Module**: The OpenTofu module responsible for VPC, subnets, Internet Gateway, NAT Gateway, and route tables
- **Security_Module**: The OpenTofu module responsible for security groups and their rules
- **IAM_Module**: The OpenTofu module responsible for IAM roles, policies, and instance profiles
- **Compute_Module**: The OpenTofu module responsible for EC2 instances (control plane, workers, benchmark-runner)
- **Load_Balancing_Module**: The OpenTofu module responsible for the internal NLB, listeners, and target groups
- **Storage_Module**: The OpenTofu module responsible for pre-created EBS volumes and StorageClass metadata outputs

## Requirements

### Requirement 1: Profile-Based Configuration

**User Story:** As a benchmark operator, I want to switch between a small development environment and a full benchmark environment using only a tfvars file, so that I can iterate cheaply during development and run valid benchmarks without editing module code.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL accept an `environment_profile` variable with valid values of "small" or "benchmark"
2. WHEN the operator invokes `tofu apply -var-file=environments/small.tfvars`, THE OpenTofu_Stack SHALL provision infrastructure using the small Environment_Profile defaults
3. WHEN the operator invokes `tofu apply -var-file=environments/benchmark.tfvars`, THE OpenTofu_Stack SHALL provision infrastructure using the benchmark Environment_Profile defaults
4. THE OpenTofu_Stack SHALL externalize all environment-specific settings (region, AZ mode, CIDR blocks, instance types, node counts, AMI IDs, EBS sizes, tags, and metadata) into tfvars files
5. THE OpenTofu_Stack SHALL preserve identical network topology, security group structure, and module composition across both profiles, differing only in capacity-related parameters

### Requirement 2: Modular Repository Structure

**User Story:** As a benchmark operator, I want the OpenTofu code organized into reusable modules at the repository root, so that each infrastructure concern is isolated and maintainable.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL place root module files (main.tf, variables.tf, outputs.tf, providers.tf, versions.tf) at the repository root
2. THE OpenTofu_Stack SHALL organize infrastructure into the following child modules: Network_Module, Security_Module, IAM_Module, Compute_Module, Load_Balancing_Module, Storage_Module, and Environment_Description_Module
3. THE OpenTofu_Stack SHALL store child modules under a `modules/` directory at the repository root
4. THE OpenTofu_Stack SHALL store tfvars files under an `environments/` directory at the repository root
5. THE OpenTofu_Stack SHALL ensure each child module accepts input variables and produces outputs without assuming a fixed Environment_Profile

### Requirement 3: VPC and Subnet Provisioning

**User Story:** As a benchmark operator, I want an isolated VPC with public and private subnets in a single Availability Zone, so that the Kubernetes cluster is network-isolated and benchmark traffic follows a controlled path.

#### Acceptance Criteria

1. THE Network_Module SHALL create one isolated VPC with a configurable CIDR block defaulting to 10.0.0.0/16 for the benchmark profile
2. THE Network_Module SHALL create one public subnet with a configurable CIDR block in the selected Availability Zone
3. THE Network_Module SHALL create one private subnet with a configurable CIDR block in the same Availability Zone as the public subnet
4. THE Network_Module SHALL output the VPC ID, subnet IDs, and CIDR blocks for use by other modules and the Environment_Description_Module

### Requirement 4: Availability Zone Selection

**User Story:** As a benchmark operator, I want to either specify an explicit AZ or have one randomly selected and persisted in state, so that benchmark runs can be randomized across AZs for validity while remaining reproducible.

#### Acceptance Criteria

1. WHEN the `availability_zone_mode` variable is set to "explicit", THE Network_Module SHALL use the AZ value provided in the `availability_zone` variable
2. WHEN the `availability_zone_mode` variable is set to "random", THE Network_Module SHALL use the hashicorp/random provider's random_shuffle resource to select one AZ from the configured region
3. THE Network_Module SHALL persist the selected AZ in OpenTofu state so that subsequent applies use the same AZ without re-randomization
4. THE Network_Module SHALL output the selected Availability Zone for inclusion in the environment description

### Requirement 5: Internet Gateway and NAT Gateway

**User Story:** As a benchmark operator, I want an Internet Gateway for public subnet routing and a NAT Gateway for private subnet egress, so that private nodes can pull container images and access AWS APIs without direct internet exposure.

#### Acceptance Criteria

1. THE Network_Module SHALL create one Internet Gateway attached to the VPC
2. THE Network_Module SHALL create one NAT Gateway in the public subnet with an allocated Elastic IP address
3. THE Network_Module SHALL create the NAT Gateway in both the "small" and "benchmark" profiles
4. THE Network_Module SHALL create a public subnet route table with a default route (0.0.0.0/0) through the Internet Gateway
5. THE Network_Module SHALL create a private subnet route table with a default route (0.0.0.0/0) through the NAT Gateway
6. THE Network_Module SHALL output route table IDs and effective routes for inclusion in the environment description

### Requirement 6: Security Groups

**User Story:** As a benchmark operator, I want explicit security groups for the benchmark-runner, NLB, control plane, and worker nodes, so that network access is restricted to only required communication paths and external interference is minimized.

#### Acceptance Criteria

1. THE Security_Module SHALL create a security group for the Benchmark_Runner that permits inbound SSH only from the Bastion_Host security group
2. THE Security_Module SHALL create a security group for the Internal_NLB that permits inbound traffic only from the Benchmark_Runner security group
3. THE Security_Module SHALL create a security group for the Control_Plane_Node that permits Kubernetes API (port 6443), etcd (ports 2379-2380), kubelet (port 10250), and SSH traffic only from authorized sources (worker nodes, Bastion_Host)
4. THE Security_Module SHALL create a security group for Worker_Nodes that permits kubelet, NodePort range (30000-32767), CNI overlay, and inter-node traffic from the control plane and other workers
5. THE Security_Module SHALL restrict all SSH access to the Bastion_Host security group only
6. THE Security_Module SHALL output all security group IDs and their complete ingress/egress rule descriptions

### Requirement 7: Benchmark-Runner Instance

**User Story:** As a benchmark operator, I want a benchmark-runner EC2 instance in the public subnet that is accessible only from the bastion host, so that I can execute Locust workloads and API calls against the internal NLB without exposing the cluster publicly.

#### Acceptance Criteria

1. THE Compute_Module SHALL create one Benchmark_Runner EC2 instance in the public subnet using instance type t3.medium by default
2. THE Compute_Module SHALL place the Benchmark_Runner in the same Availability Zone as the Kubernetes cluster
3. THE Compute_Module SHALL assign a public IP address to the Benchmark_Runner for SSH access from the Bastion_Host through the Internet Gateway
4. THE Security_Module SHALL permit the Benchmark_Runner to send traffic to the Internal_NLB
5. WHEN `tofu destroy` is executed, THE OpenTofu_Stack SHALL destroy the Benchmark_Runner along with all other managed resources

### Requirement 8: Kubernetes Control Plane Instance

**User Story:** As a benchmark operator, I want a single control-plane EC2 instance in the private subnet with configurable instance type, so that the separate Kubernetes bootstrap process can initialize a self-managed cluster.

#### Acceptance Criteria

1. THE Compute_Module SHALL create one Control_Plane_Node EC2 instance in the private subnet with a configurable instance type defaulting to m8i.xlarge for the benchmark profile
2. THE Compute_Module SHALL tag the Control_Plane_Node with role metadata (kubernetes-role=control-plane) for identification by the bootstrap process
3. THE Compute_Module SHALL output the Control_Plane_Node instance ID, private IP address, instance type, AMI ID, and root volume ID

### Requirement 9: Worker Node Groups

**User Story:** As a benchmark operator, I want two worker-node groups (amd64 and arm64) with configurable counts and instance types, so that the benchmark can evaluate autoscaler behavior on heterogeneous hardware.

#### Acceptance Criteria

1. THE Compute_Module SHALL create an amd64 worker group with a configurable instance count defaulting to 5 and instance type defaulting to c8i.4xlarge for the benchmark profile
2. THE Compute_Module SHALL create an arm64 worker group with a configurable instance count defaulting to 5 and instance type defaulting to c8g.4xlarge for the benchmark profile
3. THE Compute_Module SHALL tag each Worker_Node with architecture metadata (kubernetes-arch=amd64 or kubernetes-arch=arm64)
4. THE Compute_Module SHALL output per-node instance metadata including instance ID, private IP, instance type, AMI ID, architecture, subnet ID, and security groups
5. WHILE the Environment_Profile is "small", THE Compute_Module SHALL support reducing each worker group to a minimum of 1 node

### Requirement 10: Custom AMI Inputs

**User Story:** As a benchmark operator, I want to supply custom AMI IDs for amd64 and arm64 instances, so that I can use pre-built images with the required Kubernetes toolchain.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL accept separate AMI ID input variables for amd64 and arm64 instances
2. THE OpenTofu_Stack SHALL use the supplied AMI IDs for all EC2 instances of the corresponding architecture
3. THE OpenTofu_Stack SHALL output the AMI IDs used in each provisioning run for reproducibility auditing

### Requirement 11: Internal Network Load Balancer

**User Story:** As a benchmark operator, I want an internal NLB in the private subnet that routes benchmark traffic to the Kubernetes ingress layer, so that benchmark requests follow a realistic path without public internet exposure.

#### Acceptance Criteria

1. THE Load_Balancing_Module SHALL create one internal Network Load Balancer within the VPC private subnet
2. THE Load_Balancing_Module SHALL configure the Internal_NLB with externally configurable listener ports, target group ports, health-check paths, health-check ports, and protocol selection
3. THE Internal_NLB SHALL NOT expose any internet-facing endpoints
4. THE Load_Balancing_Module SHALL output the NLB DNS name, ARN, listener configurations, target group ARNs, and health-check settings
5. THE Security_Module SHALL restrict inbound NLB access to the Benchmark_Runner security group only

### Requirement 12: Hybrid EBS Storage Strategy

**User Story:** As a benchmark operator, I want OpenTofu to pre-create dedicated EBS volumes for etcd and control-plane state while providing IAM permissions for dynamic Kubernetes volume provisioning, so that critical state storage is deterministic and workload storage is flexible.

#### Acceptance Criteria

1. THE Storage_Module SHALL pre-create dedicated GP3 EBS volumes for etcd on the Control_Plane_Node with configurable size, IOPS, and throughput
2. THE Storage_Module SHALL output all pre-created volume IDs, sizes, types, IOPS, throughput, AZ, and intended workload mappings
3. THE IAM_Module SHALL grant EBS_CSI_Driver permissions to the Worker_Node IAM role for dynamic volume provisioning of workload storage (PostgreSQL, Kafka, Prometheus)
4. THE Storage_Module SHALL output StorageClass metadata (volume type, IOPS, throughput, filesystem type) for use by the Kubernetes bootstrap process
5. THE Compute_Module SHALL attach a configurable root EBS volume to every EC2 instance, defaulting to 100 GiB GP3 for the benchmark profile
6. WHEN `tofu destroy` is executed, THE OpenTofu_Stack SHALL destroy all EBS volumes created by the stack

### Requirement 13: IAM Roles and Instance Profiles

**User Story:** As a benchmark operator, I want least-privilege IAM roles for cluster nodes and the benchmark-runner, so that each component has only the permissions required for its function.

#### Acceptance Criteria

1. THE IAM_Module SHALL create an IAM role and instance profile for the Control_Plane_Node with permissions limited to EC2 node operations and EBS volume attachment
2. THE IAM_Module SHALL create an IAM role and instance profile for Worker_Nodes with permissions for EC2 node operations, EBS CSI driver operations, and reading from container registries
3. THE IAM_Module SHALL create an IAM role and instance profile for the Benchmark_Runner with permissions to write to the Run_Bucket and invoke NLB-accessible endpoints
4. IF the Run_Bucket name is provided, THEN THE IAM_Module SHALL scope S3 permissions to only that specific bucket ARN
5. THE IAM_Module SHALL output all IAM role names, policy names, and instance profile names

### Requirement 14: Bastion Host as External Dependency

**User Story:** As a benchmark operator, I want to supply bastion host identifiers as input variables, so that the OpenTofu stack can configure security groups referencing the bastion without managing the bastion lifecycle.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL accept input variables for the Bastion_Host instance ID, private IP or CIDR, security group ID, and optional human-readable name
2. THE OpenTofu_Stack SHALL NOT create, modify, or destroy the Bastion_Host
3. THE Security_Module SHALL reference the Bastion_Host security group ID in all SSH-permitting security group rules
4. THE OpenTofu_Stack SHALL output the Bastion_Host reference information in the environment description

### Requirement 15: S3 Run Bucket as External Dependency

**User Story:** As a benchmark operator, I want to supply the pre-existing S3 run bucket name as an input, so that OpenTofu can configure IAM permissions and output artifact path metadata without managing the bucket lifecycle.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL accept the Run_Bucket name and configurable artifact prefix structure as input variables
2. THE OpenTofu_Stack SHALL NOT create, modify, empty, or destroy the Run_Bucket
3. THE IAM_Module SHALL use the Run_Bucket name to scope S3 write permissions for relevant IAM roles
4. THE Environment_Description_Module SHALL include the Run_Bucket name and artifact prefix structure in outputs

### Requirement 16: Environment Description Generation

**User Story:** As a benchmark operator, I want OpenTofu to generate both JSON and Markdown environment reports using pure HCL templatefile() and local_file resources, so that the Full Disclosure Report has a complete, machine-readable and human-readable record of the provisioned infrastructure.

#### Acceptance Criteria

1. THE Environment_Description_Module SHALL generate a JSON environment description file using templatefile() and local_file resources
2. THE Environment_Description_Module SHALL generate a Markdown environment description file using templatefile() and local_file resources
3. THE Environment_Description_Module SHALL include in both outputs: run ID, profile name, region, AZ, VPC ID, subnet IDs, gateway IDs, route table IDs, NLB details, security group rules, IAM role names, instance metadata for all nodes, AMI IDs, EBS volume details, Run_Bucket name, artifact prefixes, Kubernetes metadata, OpenTofu version, AWS provider version, git commit hash (when available), and creation timestamp
4. THE Environment_Description_Module SHALL write output files to a configurable local path (defaulting to `artifacts/<run_id>/`)
5. IF any value affecting cost, scale, security, or reproducibility is configured, THEN THE Environment_Description_Module SHALL include that value in the output

### Requirement 17: Tagging Strategy

**User Story:** As a benchmark operator, I want all AWS resources tagged with project, profile, run ID, and ownership metadata, so that I can track costs and identify resources by benchmark run.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL apply the following tags to all taggable AWS resources: Project=KASBench, EnvironmentProfile=<profile_name>, RunId=<run_id>, ManagedBy=OpenTofu, Owner=<configured_owner>, Purpose=KubernetesAutoscalingBenchmark
2. WHEN a trial ID is applicable, THE OpenTofu_Stack SHALL include a TrialId tag on relevant resources
3. THE OpenTofu_Stack SHALL accept tag values as input variables to support cost allocation by run, trial, and profile

### Requirement 18: Teardown Safety

**User Story:** As a benchmark operator, I want `tofu destroy` to remove all stack-managed resources without affecting external dependencies, so that I can cleanly tear down environments after benchmark runs.

#### Acceptance Criteria

1. WHEN `tofu destroy` is executed, THE OpenTofu_Stack SHALL destroy all resources created by the stack (VPC, subnets, gateways, NLB, EC2 instances, EBS volumes, security groups, IAM roles)
2. THE OpenTofu_Stack SHALL NOT destroy the Run_Bucket, the Bastion_Host, externally created AMIs, or artifacts already written to S3
3. THE OpenTofu_Stack SHALL expose outputs that enable the operator to verify all required artifacts have been uploaded to the Run_Bucket before destruction

### Requirement 19: Kubernetes Bootstrap Handoff

**User Story:** As a benchmark operator, I want OpenTofu to output all information required by the separate Kubernetes bootstrap process, so that cluster initialization can proceed without manual lookups.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL output the Control_Plane_Node instance ID, private IP, and architecture
2. THE OpenTofu_Stack SHALL output all Worker_Node instance IDs, private IPs, and architectures grouped by node group
3. THE OpenTofu_Stack SHALL output all security group IDs associated with cluster nodes
4. THE OpenTofu_Stack SHALL output the Internal_NLB DNS name and target group ARNs
5. THE OpenTofu_Stack SHALL output pre-created EBS volume IDs and StorageClass metadata
6. THE OpenTofu_Stack SHALL output the Run_Bucket name and run ID

### Requirement 20: Kubernetes Metadata Pass-Through

**User Story:** As a benchmark operator, I want to supply Kubernetes-level metadata (version, CNI, runtime, Helm version, autoscaler) as input variables, so that these values appear in the environment description for reproducibility without implying OpenTofu performs the bootstrap.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL accept optional metadata input variables for Kubernetes version, CNI plugin and version, kube-proxy mode, container runtime version, Helm version, and autoscaler configuration
2. THE Environment_Description_Module SHALL include all supplied Kubernetes metadata values in both JSON and Markdown outputs
3. WHEN a metadata variable is not supplied, THE Environment_Description_Module SHALL omit that field or mark it as "not provided" rather than using a placeholder value

### Requirement 21: Observability Infrastructure Support

**User Story:** As a benchmark operator, I want OpenTofu to provide security group rules, storage support, and IAM permissions for observability components, so that Prometheus, Jaeger, and metric pipelines can be installed by the bootstrap process.

#### Acceptance Criteria

1. THE Security_Module SHALL include security group rules permitting Prometheus scraping traffic (port 9090) and node-exporter traffic (port 9100) between Worker_Nodes
2. THE IAM_Module SHALL include permissions for Worker_Nodes to attach EBS volumes used by Prometheus and other stateful observability workloads via the EBS_CSI_Driver
3. THE OpenTofu_Stack SHALL accept optional observability retention metadata variables and include them in the environment description when provided
4. THE Storage_Module SHALL output StorageClass metadata suitable for Prometheus persistent volume provisioning

### Requirement 22: Debug Retention Mode

**User Story:** As a benchmark operator, I want an optional debug-retention mode for the small profile that prevents accidental destruction of selected resources, so that I can preserve state during iterative development.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL accept a `debug_retention_enabled` boolean variable defaulting to false
2. WHILE `debug_retention_enabled` is true and the Environment_Profile is "small", THE OpenTofu_Stack SHALL apply lifecycle prevent_destroy rules to EC2 instances and EBS volumes
3. WHILE the Environment_Profile is "benchmark", THE OpenTofu_Stack SHALL ignore the `debug_retention_enabled` variable and permit full destruction

### Requirement 23: Reproducibility Outputs

**User Story:** As a benchmark operator, I want OpenTofu to capture and output all effective configuration values, versioning information, and timestamps, so that any benchmark run can be fully reproduced or audited.

#### Acceptance Criteria

1. THE OpenTofu_Stack SHALL output the OpenTofu version and AWS provider version used during the apply
2. THE OpenTofu_Stack SHALL output the git commit hash of the infrastructure repository when available
3. THE OpenTofu_Stack SHALL output a creation timestamp recording when the infrastructure was provisioned
4. THE OpenTofu_Stack SHALL output all effective variable values that affect infrastructure sizing, networking, security, or benchmark behavior
5. THE Environment_Description_Module SHALL include checksums of generated configuration and output artifact files
