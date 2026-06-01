resource "aws_ecs_cluster" "this" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = local.services

  name              = "/ecs/${local.name_prefix}/${each.value.module}"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "service" {
  for_each = local.services

  family                   = "${local.name_prefix}-${each.value.module}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.service_cpu
  memory                   = var.service_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = each.value.module
      image     = "${local.shared.ecr_repository_urls[each.key]}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = each.value.container_port
          hostPort      = each.value.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for name, value in merge(
          {
            PORT = tostring(each.value.container_port)
          },
          each.value.extra_environment,
          lookup(var.service_environment, each.key, {})
          ) : {
          name  = name
          value = value
        }
      ]

      secrets = concat(
        [
          for secret_name in each.value.secret_names : {
            name      = secret_name
            valueFrom = local.shared.service_secret_arns["${each.key}/${secret_name}"]
          }
        ],
        each.key == "dispatch" ? [
          {
            name      = "JWT_SECRET"
            valueFrom = local.shared.service_secret_arns["user/JWT_SECRET"]
          }
        ] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.service[each.key].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "service" {
  for_each = local.services

  name            = "${local.name_prefix}-${each.value.module}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service[each.key].arn
  desired_count   = lookup(var.service_desired_counts, each.key, var.service_desired_count)
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  network_configuration {
    subnets          = local.shared.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.service[each.key].arn
    container_name   = each.value.module
    container_port   = each.value.container_port
  }

  depends_on = [aws_lb_listener.http]
}
