resource "aws_cloudwatch_log_group" "geo_consumer" {
  name              = "/ecs/${local.name_prefix}/vehicle-geo-consumer"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "geo_consumer" {
  family                   = "${local.name_prefix}-vehicle-geo-consumer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "vehicle-geo-consumer"
      image     = "${data.aws_ecr_repository.baro_kafka_consumer.repository_url}:latest"
      essential = true

      environment = [
        { name = "KAFKA_BOOTSTRAP_SERVERS",    value = "kafka.${aws_service_discovery_private_dns_namespace.this.name}:9092" },
        { name = "KAFKA_GROUP_ID",             value = "baro-geo-consumer-group" },
        { name = "KAFKA_TOPIC",                value = "vehicle-data-topic" },
        { name = "TIMESCALEDB_CONSUMER_ENABLED", value = "false" },
        { name = "GEO_CONSUMER_ENABLED",       value = "true" },
        { name = "REDIS_HOST",                 value = aws_elasticache_cluster.redis.cache_nodes[0].address },
        { name = "REDIS_PORT",                 value = "6379" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.geo_consumer.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "geo_consumer" {
  name            = "${local.name_prefix}-vehicle-geo-consumer"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.geo_consumer.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  enable_execute_command             = true

  network_configuration {
    subnets          = [for subnet in aws_subnet.private : subnet.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  tags = local.common_tags
}

data "aws_ecr_repository" "baro_kafka_consumer" {
  name = "baro-kafka-consumer"
}
