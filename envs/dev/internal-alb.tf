resource "aws_lb" "internal" {
  name               = "${local.name_prefix}-int"
  load_balancer_type = "application"
  internal           = true
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = [for subnet in aws_subnet.private : subnet.id]
}

resource "aws_lb_listener" "internal_https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "baro dev internal alb"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "internal_service" {
  for_each = local.services

  listener_arn = aws_lb_listener.internal_https.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/internal/${each.key}/*"]
    }
  }
}
