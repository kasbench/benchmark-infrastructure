# =============================================================================
# Security Groups and Rules for KASBench Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# Benchmark-Runner Security Group
# SSH from bastion only, all egress
# -----------------------------------------------------------------------------

resource "aws_security_group" "benchmark_runner" {
  name_prefix = "kasbench-runner-"
  vpc_id      = var.vpc_id
  description = "Benchmark-runner: SSH from bastion only"
  tags        = merge(var.tags, { Name = "kasbench-runner-sg" })
}

resource "aws_security_group_rule" "runner_ssh_in" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.benchmark_runner.id
  description       = "SSH from anywhere (bastion peering unreliable)"
}

resource "aws_security_group_rule" "runner_api_in" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.benchmark_runner.id
  description       = "Runner API from bastion host"
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

# -----------------------------------------------------------------------------
# NLB Security Group
# All TCP from benchmark-runner SG only
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Control-Plane Security Group
# 6443 from workers + runner, 2379-2380 self, 10250 from workers,
# SSH from bastion, all egress
# -----------------------------------------------------------------------------

resource "aws_security_group" "control_plane" {
  name_prefix = "kasbench-cp-"
  vpc_id      = var.vpc_id
  description = "Kubernetes control plane"
  tags        = merge(var.tags, { Name = "kasbench-cp-sg" })
}

resource "aws_security_group_rule" "cp_all_from_workers" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker_node.id
  security_group_id        = aws_security_group.control_plane.id
  description              = "All traffic from worker nodes"
}

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
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.bastion_ssh_cidr]
  security_group_id = aws_security_group.control_plane.id
  description       = "SSH from bastion"
}

resource "aws_security_group_rule" "cp_ssh_from_runner" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.benchmark_runner.id
  security_group_id        = aws_security_group.control_plane.id
  description              = "SSH from benchmark-runner"
}

resource "aws_security_group_rule" "cp_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.control_plane.id
  description       = "Allow all outbound"
}

# -----------------------------------------------------------------------------
# Worker-Node Security Group
# 10250 from CP, 30000-32767 self, 9090/9100 self (observability),
# SSH from bastion, all egress
# -----------------------------------------------------------------------------

resource "aws_security_group" "worker_node" {
  name_prefix = "kasbench-worker-"
  vpc_id      = var.vpc_id
  description = "Kubernetes worker nodes"
  tags        = merge(var.tags, { Name = "kasbench-worker-sg" })
}

resource "aws_security_group_rule" "worker_all_from_cp" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.worker_node.id
  description              = "All traffic from control plane"
}

resource "aws_security_group_rule" "worker_all_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.worker_node.id
  description       = "All traffic between worker nodes"
}

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
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.bastion_ssh_cidr]
  security_group_id = aws_security_group.worker_node.id
  description       = "SSH from bastion"
}

resource "aws_security_group_rule" "worker_ssh_from_runner" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.benchmark_runner.id
  security_group_id        = aws_security_group.worker_node.id
  description              = "SSH from benchmark-runner"
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
