resource "aws_ecs_cluster" "this" {
  count = var.runtime_enabled ? 1 : 0

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
      image     = "${aws_ecr_repository.service[each.key].repository_url}:${var.image_tag}"
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
        } if !contains(each.value.secret_names, name)
      ]

      secrets = concat(
        [
          for secret_name in each.value.secret_names : {
            name      = secret_name
            valueFrom = aws_secretsmanager_secret.service["${each.key}/${secret_name}"].arn
          } if secret_name != "INTERNAL_API_KEY"
        ],
        each.key == "dispatch" ? [
          {
            name      = "DISPATCH_DB_USERNAME"
            valueFrom = "${aws_secretsmanager_secret.rds_master.arn}:username::"
          },
          {
            name      = "DISPATCH_DB_PASSWORD"
            valueFrom = "${aws_secretsmanager_secret.rds_master.arn}:password::"
          }
        ] : [],
        each.key == "user" ? [
          {
            name      = "USER_DB_USERNAME"
            valueFrom = "${aws_secretsmanager_secret.rds_master.arn}:username::"
          },
          {
            name      = "USER_DB_PASSWORD"
            valueFrom = "${aws_secretsmanager_secret.rds_master.arn}:password::"
          }
        ] : [],
        each.key == "gateway" ? [
          {
            name      = "JWT_SECRET"
            valueFrom = aws_secretsmanager_secret.service["user/JWT_SECRET"].arn
          }
        ] : [],
        contains(["control", "dispatch", "relocation"], each.key) ? [
          {
            name      = "INTERNAL_API_KEY"
            valueFrom = data.aws_secretsmanager_secret.internal_api_key.arn
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
  for_each = local.runtime_services

  name            = "${local.name_prefix}-${each.value.module}"
  cluster         = aws_ecs_cluster.this[0].id
  task_definition = aws_ecs_task_definition.service[each.key].arn
  desired_count   = lookup(var.service_desired_counts, each.key, var.service_desired_count)
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  network_configuration {
    subnets          = [for subnet in aws_subnet.private : subnet.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = contains(keys(local.public_alb_services), each.key) ? [each.value] : []

    content {
      target_group_arn = aws_lb_target_group.service[each.key].arn
      container_name   = load_balancer.value.module
      container_port   = load_balancer.value.container_port
    }
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service[each.key].arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.internal_service[each.key].arn
    container_name   = each.value.module
    container_port   = each.value.container_port
  }

  depends_on = [
    aws_lb_listener.https,
    aws_lb_listener.internal_https
  ]
}
