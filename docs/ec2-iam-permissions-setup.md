# EC2 Instance IAM Permissions for KASBench Infrastructure Deployment

This document details the IAM setup required for an EC2 instance (the "bastion" or "deployer" host) to run `tofu apply` and provision the full KASBench benchmark infrastructure.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Context](#architecture-context)
3. [IAM Role and Instance Profile Setup](#iam-role-and-instance-profile-setup)
4. [Required IAM Policy](#required-iam-policy)
5. [Trust Policy (Assume Role)](#trust-policy-assume-role)
6. [Attaching the Instance Profile](#attaching-the-instance-profile)
7. [OpenTofu State Considerations](#opentofu-state-considerations)
8. [Security Recommendations](#security-recommendations)
9. [Verification Steps](#verification-steps)

---

## Overview

The KASBench infrastructure provisions a full Kubernetes cluster environment in AWS including:

- VPC with public/private subnets, Internet Gateway, NAT Gateway
- VPC Peering to an existing bastion VPC
- Security Groups (4 groups with ~20+ rules)
- IAM Roles, Policies, and Instance Profiles (control-plane, worker, runner)
- EC2 Instances (control plane, workers amd64/arm64, benchmark runner)
- EBS Volumes (etcd dedicated volume)
- Network Load Balancer (internal, with target groups and listeners)
- EC2 Key Pairs
- Elastic IPs

The deployer EC2 instance needs permissions to **create, read, update, and delete** all of these resources.

---

## Architecture Context

```
┌─────────────────────────────────────────────┐
│  Deployer EC2 Instance (Bastion VPC)        │
│  - Runs: tofu apply/destroy                 │
│  - Needs: IAM Instance Profile              │
│           with full provisioning permissions │
└──────────────────┬──────────────────────────┘
                   │ AWS API calls
                   ▼
┌─────────────────────────────────────────────┐
│  KASBench VPC (10.0.0.0/16)                 │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐  │
│  │ Control  │ │ Workers  │ │ Benchmark  │  │
│  │ Plane    │ │ (amd64/  │ │ Runner     │  │
│  │          │ │  arm64)  │ │            │  │
│  └──────────┘ └──────────┘ └────────────┘  │
│  ┌──────────┐ ┌──────────┐                  │
│  │ NLB      │ │ etcd EBS │                  │
│  └──────────┘ └──────────┘                  │
└─────────────────────────────────────────────┘
```

---

## IAM Role and Instance Profile Setup

### Step 1: Create the IAM Role

```bash
aws iam create-role \
  --role-name kasbench-deployer \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role for EC2 instance that deploys KASBench infrastructure via OpenTofu" \
  --tags Key=Project,Value=KASBench Key=Purpose,Value=InfrastructureDeployer
```

### Step 2: Create and Attach the Policy

```bash
aws iam create-policy \
  --policy-name kasbench-deployer-policy \
  --policy-document file://deployer-policy.json \
  --description "Permissions for KASBench infrastructure provisioning"

aws iam attach-role-policy \
  --role-name kasbench-deployer \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/kasbench-deployer-policy
```

### Step 3: Create Instance Profile and Associate

```bash
aws iam create-instance-profile \
  --instance-profile-name kasbench-deployer

aws iam add-role-to-instance-profile \
  --instance-profile-name kasbench-deployer \
  --role-name kasbench-deployer
```

---

## Required IAM Policy

The following policy grants the minimum permissions needed to provision and tear down the full KASBench infrastructure. It is split into logical statements by AWS service.

Save this as `deployer-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2FullLifecycle",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:RebootInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
        "ec2:ModifyInstanceAttribute"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2NetworkResources",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:DescribeVpcAttribute",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:DescribeAddressesAttribute",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:DescribeNatGateways",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:ReplaceRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2VpcPeering",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpcPeeringConnection",
        "ec2:AcceptVpcPeeringConnection",
        "ec2:DeleteVpcPeeringConnection",
        "ec2:DescribeVpcPeeringConnections",
        "ec2:ModifyVpcPeeringConnectionOptions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2SecurityGroups",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
        "ec2:UpdateSecurityGroupRuleDescriptionsEgress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2EBSVolumes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumeStatus",
        "ec2:DescribeVolumeAttribute",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2KeyPairs",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateKeyPair",
        "ec2:DeleteKeyPair",
        "ec2:DescribeKeyPairs",
        "ec2:ImportKeyPair"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Tags",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2AvailabilityZones",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeRegions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2NetworkInterfaces",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ElasticLoadBalancingV2",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags",
        "elasticloadbalancing:DescribeTags",
        "elasticloadbalancing:SetSecurityGroups"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRolesAndPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:UpdateRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicies",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMInstanceProfiles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:ListInstanceProfiles",
        "iam:ListInstanceProfilesForRole",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/kasbench-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Sid": "S3BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::kasbench-*",
        "arn:aws:s3:::kasbench-*/*"
      ]
    },
    {
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

---

## Trust Policy (Assume Role)

Save this as `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

---

## Attaching the Instance Profile

### For an existing EC2 instance:

```bash
aws ec2 associate-iam-instance-profile \
  --iam-instance-profile Name=kasbench-deployer \
  --instance-id i-XXXXXXXXXXXX
```

### For a new EC2 instance (at launch time):

```bash
aws ec2 run-instances \
  --image-id ami-XXXXXXXXXXXX \
  --instance-type t3.medium \
  --iam-instance-profile Name=kasbench-deployer \
  --key-name your-key-name \
  --subnet-id subnet-XXXXXXXXXXXX \
  ...
```

### Via Terraform/OpenTofu (if managing the deployer via IaC):

```hcl
resource "aws_instance" "deployer" {
  ami                  = "ami-XXXXXXXXXXXX"
  instance_type        = "t3.medium"
  iam_instance_profile = aws_iam_instance_profile.kasbench_deployer.name
  # ...
}
```

---

## OpenTofu State Considerations

This project uses **local state** (no remote backend is configured). This means:

1. **State file lives on the EC2 instance's disk** at `terraform.tfstate`.
2. If the deployer EC2 instance is terminated, the state file is **lost**. Consider:
   - Backing up `terraform.tfstate` to S3 after each apply/destroy.
   - Or configuring a remote S3 backend (which would require additional S3/DynamoDB permissions).

### Optional: Remote Backend Permissions (if added later)

If you add an S3 backend with DynamoDB locking, add these permissions:

```json
{
  "Sid": "TerraformStateBackend",
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket",
    "s3:GetBucketVersioning"
  ],
  "Resource": [
    "arn:aws:s3:::YOUR-STATE-BUCKET",
    "arn:aws:s3:::YOUR-STATE-BUCKET/*"
  ]
},
{
  "Sid": "TerraformStateLocking",
  "Effect": "Allow",
  "Action": [
    "dynamodb:GetItem",
    "dynamodb:PutItem",
    "dynamodb:DeleteItem",
    "dynamodb:DescribeTable"
  ],
  "Resource": "arn:aws:dynamodb:*:*:table/YOUR-LOCK-TABLE"
}
```

---

## Security Recommendations

### 1. Scope Down Where Possible

The policy above uses `"Resource": "*"` for most EC2 and IAM actions because OpenTofu needs to create resources with dynamic names/IDs. To tighten this:

- **Tag-based conditions**: Add conditions like `aws:RequestTag/Project = KASBench` where supported.
- **Region restriction**: Add a global condition to limit to your target region:

```json
"Condition": {
  "StringEquals": {
    "aws:RequestedRegion": "us-east-1"
  }
}
```

### 2. Use a Permissions Boundary

Create a permissions boundary to cap what the deployer role can ever do:

```bash
aws iam put-role-permissions-boundary \
  --role-name kasbench-deployer \
  --permissions-boundary arn:aws:iam::<ACCOUNT_ID>:policy/kasbench-deployer-boundary
```

### 3. IAM Role Scoping

The `iam:PassRole` permission is scoped to roles named `kasbench-*`. This prevents the deployer from passing arbitrary roles to EC2 instances. Similarly, scope IAM create/delete if possible:

```json
"Resource": "arn:aws:iam::*:role/kasbench-*"
```

Note: This only works if you can guarantee all resource names start with `kasbench-`. The current HCL uses `name_prefix = "kasbench-"` for all IAM resources, so this is safe.

### 4. VPC Peering Security

The infrastructure creates a VPC peering connection and auto-accepts it. The deployer needs permissions for both the source and peer VPCs. If the bastion VPC is in a different account, you'll need cross-account peering setup instead.

### 5. Instance Metadata Service

Ensure the deployer EC2 instance uses IMDSv2 (Instance Metadata Service Version 2) to prevent SSRF-based credential theft:

```bash
aws ec2 modify-instance-metadata-options \
  --instance-id i-XXXXXXXXXXXX \
  --http-tokens required \
  --http-endpoint enabled
```

---

## Verification Steps

After setting up the IAM role and instance profile, verify from the deployer EC2 instance:

### 1. Confirm the instance profile is attached

```bash
curl -s http://169.254.169.254/latest/meta-data/iam/info | python3 -m json.tool
# Should show the kasbench-deployer role ARN
```

### 2. Verify AWS identity

```bash
aws sts get-caller-identity
# Should show the role ARN for kasbench-deployer
```

### 3. Test key permissions

```bash
# EC2
aws ec2 describe-vpcs --region us-east-1
aws ec2 describe-availability-zones --region us-east-1

# IAM
aws iam list-roles --path-prefix /

# ELB
aws elbv2 describe-load-balancers --region us-east-1
```

### 4. Run OpenTofu plan

```bash
cd /path/to/benchmark-infrastructure
tofu init
tofu plan -var-file=environments/small-test.tfvars
```

If the plan completes without authorization errors, the permissions are correctly configured.

### 5. Full apply (when ready)

```bash
tofu apply -var-file=environments/small-test.tfvars
```

---

## Summary of AWS Services and Actions Required

| Service | Purpose | Key Actions |
|---------|---------|-------------|
| EC2 | Instances, VPC, Subnets, SGs, EBS, Key Pairs, EIPs, NAT GW, IGW, Route Tables, VPC Peering | Full lifecycle (Create/Delete/Describe/Modify) |
| Elastic Load Balancing v2 | Internal NLB, Target Groups, Listeners | Full lifecycle |
| IAM | Roles, Policies, Instance Profiles for managed nodes | Create/Delete/Get/Attach/Detach + PassRole |
| S3 | Run bucket access (artifacts) | Get/Put/Delete/List on `kasbench-*` buckets |
| STS | Caller identity verification | GetCallerIdentity |

---

## Appendix: Tightened Policy (Resource-Scoped)

If you want maximum restriction and can accept maintaining ARN references, here's a tightened version for the IAM section:

```json
{
  "Sid": "IAMRolesScoped",
  "Effect": "Allow",
  "Action": [
    "iam:CreateRole",
    "iam:DeleteRole",
    "iam:GetRole",
    "iam:TagRole",
    "iam:UntagRole",
    "iam:ListRoleTags",
    "iam:ListAttachedRolePolicies",
    "iam:ListRolePolicies",
    "iam:AttachRolePolicy",
    "iam:DetachRolePolicy",
    "iam:PutRolePolicy",
    "iam:DeleteRolePolicy",
    "iam:GetRolePolicy"
  ],
  "Resource": "arn:aws:iam::*:role/kasbench-*"
},
{
  "Sid": "IAMPoliciesScoped",
  "Effect": "Allow",
  "Action": [
    "iam:CreatePolicy",
    "iam:DeletePolicy",
    "iam:GetPolicy",
    "iam:GetPolicyVersion",
    "iam:ListPolicyVersions",
    "iam:CreatePolicyVersion",
    "iam:DeletePolicyVersion"
  ],
  "Resource": "arn:aws:iam::*:policy/kasbench-*"
},
{
  "Sid": "IAMInstanceProfilesScoped",
  "Effect": "Allow",
  "Action": [
    "iam:CreateInstanceProfile",
    "iam:DeleteInstanceProfile",
    "iam:GetInstanceProfile",
    "iam:ListInstanceProfilesForRole",
    "iam:AddRoleToInstanceProfile",
    "iam:RemoveRoleFromInstanceProfile",
    "iam:TagInstanceProfile",
    "iam:UntagInstanceProfile"
  ],
  "Resource": "arn:aws:iam::*:instance-profile/kasbench-*"
}
```

This works because all IAM resources in the HCL use `name_prefix = "kasbench-"`.

---

## Appendix: Required Software on Deployer EC2

Ensure the deployer instance has:

| Software | Version | Purpose |
|----------|---------|---------|
| OpenTofu | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI v2 | Latest | Verification and debugging |
| Git | Latest | Clone the infrastructure repo |

```bash
# Install OpenTofu (example for Amazon Linux 2023 / Ubuntu)
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method rpm  # or --install-method deb for Ubuntu

# Verify
tofu version
aws --version
```
