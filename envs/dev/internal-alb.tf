resource "aws_lb" "internal" {
  count              = var.runtime_enabled ? 1 : 0
  name               = "${local.name_prefix}-int"
  load_balancer_type = "application"
  internal           = true
  security_groups    = [aws_security_group.internal_alb[0].id]
  subnets            = [for subnet in aws_subnet.private : subnet.id]
}

resource "aws_lb_listener" "internal_https" {
  count             = var.runtime_enabled ? 1 : 0
  load_balancer_arn = aws_lb.internal[0].arn
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

resource "aws_lb_target_group" "internal_service" {
  for_each = local.internal_alb_services

  name        = "${local.name_prefix}-int-${each.key}"
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = each.value.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener_rule" "gateway_prometheus_metrics" {
  count = contains(keys(local.internal_alb_services), "gateway") ? 1 : 0

  listener_arn = aws_lb_listener.internal_https[0].arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_service["gateway"].arn
  }

  condition {
    host_header {
      values = ["internal-${local.app_domain_name}"]
    }
  }

  condition {
    path_pattern {
      values = ["/actuator/prometheus"]
    }
  }
}

resource "aws_lb_listener_rule" "service_metrics" {
  for_each = {
    for key, config in local.service_metrics_rules : key => config
    if contains(keys(local.internal_alb_services), key)
  }

  listener_arn = aws_lb_listener.internal_https[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_service[each.key].arn
  }

  condition {
    host_header {
      values = [each.value.host]
    }
  }

  condition {
    path_pattern {
      values = ["/actuator/health", "/actuator/prometheus"]
    }
  }
}

resource "aws_lb_listener_rule" "internal_service" {
  for_each = local.internal_alb_services

  listener_arn = aws_lb_listener.internal_https[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_service[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/internal/${each.key}/*"]
    }
  }
}
