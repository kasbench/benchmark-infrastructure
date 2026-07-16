# =============================================================================
# Public Network Load Balancer for KASBench Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# Internet-facing NLB
# Placed in public subnet so the benchmark runner (and external clients) can
# reach the Envoy gateway via NodePort on the worker nodes.
# -----------------------------------------------------------------------------

resource "aws_lb" "internal" {
  name_prefix        = "kasb-"
  internal           = false
  load_balancer_type = "network"
  subnets            = [var.public_subnet_id]
  security_groups    = [var.nlb_sg_id]

  tags = merge(var.tags, { Name = "kasbench-public-nlb" })
}

# -----------------------------------------------------------------------------
# Target Groups
# One per listener with configurable health checks
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Listeners
# Forward traffic to corresponding target groups
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Target Group Attachments
# Register all worker nodes in every target group so the NLB can forward
# traffic to the Envoy proxy NodePort (30080) on any worker.
# -----------------------------------------------------------------------------

locals {
  # Build a flat list: one entry per (listener × worker instance)
  tg_attachments = flatten([
    for l in var.nlb_config.listeners : [
      for id in var.worker_instance_ids : {
        key         = "${l.name}-${id}"
        listener    = l.name
        instance_id = id
        port        = l.target_port
      }
    ]
  ])
}

resource "aws_lb_target_group_attachment" "workers" {
  for_each = { for a in local.tg_attachments : a.key => a }

  target_group_arn = aws_lb_target_group.ingress[each.value.listener].arn
  target_id        = each.value.instance_id
  port             = each.value.port
}
