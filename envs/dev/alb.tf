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
    target_group_arn = try(aws_lb_target_group.service["mobile"].arn, null)

    dynamic "fixed_response" {
      for_each = contains(keys(local.ecs_codedeploy_services), "mobile") ? [] : [1]

      content {
        content_type = "text/plain"
        message_body = "baro dev alb"
        status_code  = "404"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      default_action,
    ]
  }
}

resource "aws_lb_listener_rule" "mobile_codedeploy_bootstrap" {
  count = contains(keys(local.ecs_codedeploy_services), "mobile") ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 50000

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service["mobile"].arn
  }

  condition {
    path_pattern {
      values = ["/__codedeploy/mobile-bootstrap"]
    }
  }
}

resource "terraform_data" "mobile_codedeploy_listener_bootstrap" {
  count = contains(keys(local.ecs_codedeploy_services), "mobile") ? 1 : 0

  input = {
    blue_target_group_arn  = aws_lb_target_group.service["mobile"].arn
    green_target_group_arn = aws_lb_target_group.service_green["mobile"].arn
    listener_arn           = aws_lb_listener.https[0].arn
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      target_count() {
        aws elbv2 describe-target-health \
          --region ${var.aws_region} \
          --target-group-arn "$1" \
          --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy` || TargetHealth.State==`initial`])' \
          --output text
      }

      current_target_group_arn="$(aws elbv2 describe-listeners \
        --region ${var.aws_region} \
        --listener-arns ${self.input.listener_arn} \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text)"

      if [ -n "$current_target_group_arn" ] && [ "$current_target_group_arn" != "None" ] && [ "$(target_count "$current_target_group_arn")" -gt 0 ]; then
        exit 0
      fi

      next_target_group_arn="${self.input.blue_target_group_arn}"
      if [ "$(target_count "${self.input.green_target_group_arn}")" -gt 0 ]; then
        next_target_group_arn="${self.input.green_target_group_arn}"
      fi

      aws elbv2 modify-listener \
        --region ${var.aws_region} \
        --listener-arn ${self.input.listener_arn} \
        --default-actions Type=forward,TargetGroupArn="$next_target_group_arn"
    EOT
  }

  depends_on = [
    aws_lb_listener_rule.mobile_codedeploy_bootstrap,
  ]
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
