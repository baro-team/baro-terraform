resource "aws_lb" "this" {
  count = var.runtime_enabled ? 1 : 0

  name               = local.name_prefix
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
}

resource "aws_lb_target_group" "service" {
  for_each = local.public_alb_services

  name        = "${local.name_prefix}-${each.key}"
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

resource "aws_lb_target_group" "service_green" {
  for_each = local.ecs_codedeploy_services

  name        = "${local.name_prefix}-${each.key}-green"
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

resource "aws_lb_listener" "http" {
  count = var.runtime_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.runtime_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  default_action {
    type             = contains(keys(local.ecs_codedeploy_services), "mobile") ? "forward" : "fixed-response"
    target_group_arn = contains(keys(local.ecs_codedeploy_services), "mobile") ? aws_lb_target_group.service["mobile"].arn : null

    dynamic "fixed_response" {
      for_each = contains(keys(local.ecs_codedeploy_services), "mobile") ? [] : [1]

      content {
        content_type = "text/plain"
        message_body = "baro dev alb"
        status_code  = "404"
      }
    }
  }
}
resource "aws_lb_listener_rule" "block_internal" {
  count        = var.runtime_enabled ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/internal/*", "*/internal/*"]
    }
  }
}

resource "aws_lb_listener_rule" "service" {
  for_each = local.public_alb_listener_rules

  listener_arn = aws_lb_listener.https[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.value.service_key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }
}
