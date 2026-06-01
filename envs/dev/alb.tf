resource "aws_lb" "this" {
  name               = local.name_prefix
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
}

resource "aws_lb_target_group" "service" {
  for_each = local.services

  name        = "${local.name_prefix}-${each.key}"
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/actuator/health"
    matcher             = "200-499"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "baro dev alb"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "service" {
  for_each = local.services

  listener_arn = aws_lb_listener.http.arn
  priority     = 100 + index(keys(local.services), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }
}

resource "aws_lb_listener_rule" "user_docs" {
  count = contains(var.enabled_services, "user") ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service["user"].arn
  }

  condition {
    path_pattern {
      values = [
        "/swagger-ui.html",
        "/swagger-ui/*",
        "/api-docs",
        "/api-docs/*",
        "/v3/api-docs",
        "/v3/api-docs/*",
      ]
    }
  }
}
