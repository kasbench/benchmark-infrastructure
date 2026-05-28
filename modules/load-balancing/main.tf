# =============================================================================
# Internal Network Load Balancer for KASBench Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# Internal NLB
# Placed in private subnet, never internet-facing
# -----------------------------------------------------------------------------

resource "aws_lb" "internal" {
  name_prefix        = "kasb-"
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.private_subnet_id]
  security_groups    = [var.nlb_sg_id]

  tags = merge(var.tags, { Name = "kasbench-internal-nlb" })
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
