resource "aws_codedeploy_app" "ecs" {
  count = length(local.ecs_codedeploy_services) > 0 ? 1 : 0

  name             = "${local.name_prefix}-baro-mobile"
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "ecs" {
  for_each = local.ecs_codedeploy_services

  app_name               = aws_codedeploy_app.ecs[0].name
  deployment_group_name  = "${local.name_prefix}-${each.value.module}"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  auto_rollback_configuration {
    enabled = true
    events = [
      "DEPLOYMENT_FAILURE",
      "DEPLOYMENT_STOP_ON_ALARM",
      "DEPLOYMENT_STOP_ON_REQUEST",
    ]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.this[0].name
    service_name = aws_ecs_service.codedeploy[each.key].name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.https[0].arn]
      }

      target_group {
        name = aws_lb_target_group.service[each.key].name
      }

      target_group {
        name = aws_lb_target_group.service_green[each.key].name
      }
    }
  }
}
