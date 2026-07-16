output "nlb_metadata" {
  description = "Public NLB metadata including DNS name, ARN, listeners, and target groups"
  value = {
    dns_name = aws_lb.internal.dns_name
    arn      = aws_lb.internal.arn
    scheme   = "internet-facing"
    listeners = { for k, l in aws_lb_listener.ingress : k => {
      port     = l.port
      protocol = l.protocol
    } }
    target_groups = { for k, tg in aws_lb_target_group.ingress : k => {
      arn  = tg.arn
      port = tg.port
    } }
  }
}
