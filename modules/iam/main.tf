# IAM Module - Roles, Policies, and Instance Profiles
# Implements least-privilege IAM for control plane, worker nodes, and benchmark-runner

# Shared EC2 assume-role trust policy
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# =============================================================================
# Control Plane Role
# =============================================================================

resource "aws_iam_role" "control_plane" {
  name_prefix        = "kasbench-cp-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
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

resource "aws_iam_role_policy_attachment" "control_plane_ebs_csi" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "control_plane_s3_full" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "control_plane_ssm" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "control_plane_cloudwatch" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "control_plane" {
  name_prefix = "kasbench-cp-"
  role        = aws_iam_role.control_plane.name
}

# =============================================================================
# Worker Node Role (includes EBS CSI permissions)
# =============================================================================

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

resource "aws_iam_role_policy_attachment" "worker_node_ebs_csi" {
  role       = aws_iam_role.worker_node.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "worker_node_s3_full" {
  role       = aws_iam_role.worker_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "worker_node_ssm" {
  role       = aws_iam_role.worker_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "worker_node_cloudwatch" {
  role       = aws_iam_role.worker_node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "worker_node" {
  name_prefix = "kasbench-worker-"
  role        = aws_iam_role.worker_node.name
}

# =============================================================================
# Benchmark Runner Role
# =============================================================================

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
