resource "random_password" "rds_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "this" {
  count = var.runtime_enabled ? 1 : 0

  name       = local.name_prefix
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = {
    Name = local.name_prefix
  }
}

resource "aws_security_group" "rds" {
  count = var.runtime_enabled ? 1 : 0

  name        = "${local.name_prefix}-rds"
  description = "Allow PostgreSQL from ECS tasks"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "PostgreSQL from SSM bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "On-premise VPN access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.onprem_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}

resource "aws_db_instance" "postgres" {
  count = var.runtime_enabled ? 1 : 0

  identifier = "${local.name_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.rds_database_name
  username = var.rds_master_username
  password = random_password.rds_master.result

  db_subnet_group_name   = aws_db_subnet_group.this[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  publicly_accessible    = false

  backup_retention_period = 1
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:00-sun:20:00"

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}

resource "aws_secretsmanager_secret" "rds_master" {
  name                    = "${local.name_prefix}/rds/master"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id

  secret_string = jsonencode({
    engine   = "postgres"
    host     = var.runtime_enabled ? aws_db_instance.postgres[0].address : ""
    port     = var.runtime_enabled ? aws_db_instance.postgres[0].port : 5432
    dbname   = var.runtime_enabled ? aws_db_instance.postgres[0].db_name : var.rds_database_name
    username = var.rds_master_username
    password = random_password.rds_master.result
    jdbc_url = var.runtime_enabled ? "jdbc:postgresql://${aws_db_instance.postgres[0].address}:${aws_db_instance.postgres[0].port}/${aws_db_instance.postgres[0].db_name}" : ""
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_cloudwatch_log_group" "db_init" {
  name              = "/ecs/${local.name_prefix}/db-init"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "db_init" {
  count = var.runtime_enabled ? 1 : 0

  family                   = "${local.name_prefix}-db-init"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "db-init"
      image     = "postgres:16-alpine"
      essential = true
      command = [
        "sh",
        "-c",
        join(" ", [
          "psql -v ON_ERROR_STOP=1",
          "-h ${aws_db_instance.postgres[0].address}",
          "-p ${aws_db_instance.postgres[0].port}",
          "-U ${aws_db_instance.postgres[0].username}",
          "-d ${aws_db_instance.postgres[0].db_name}",
          "-c \"CREATE SCHEMA IF NOT EXISTS user_service; CREATE SCHEMA IF NOT EXISTS dispatch_service; CREATE SCHEMA IF NOT EXISTS relocation_service; CREATE SCHEMA IF NOT EXISTS control_service;\""
        ])
      ]
      environment = [
        {
          name  = "PGDATABASE"
          value = aws_db_instance.postgres[0].db_name
        }
      ]
      secrets = [
        {
          name      = "PGPASSWORD"
          valueFrom = "${aws_secretsmanager_secret.rds_master.arn}:password::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.db_init.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_secretsmanager_secret_version" "relocation_db_url" {
  count = 1

  secret_id     = aws_secretsmanager_secret.service["relocation/RELOCATION_DB_URL"].id
  secret_string = var.runtime_enabled ? "jdbc:postgresql://${aws_db_instance.postgres[0].address}:${aws_db_instance.postgres[0].port}/${aws_db_instance.postgres[0].db_name}?currentSchema=relocation_service" : ""

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret_version" "relocation_db_username" {
  count = 1

  secret_id     = aws_secretsmanager_secret.service["relocation/RELOCATION_DB_USERNAME"].id
  secret_string = var.runtime_enabled ? aws_db_instance.postgres[0].username : var.rds_master_username

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret_version" "relocation_db_password" {
  count = 1

  secret_id     = aws_secretsmanager_secret.service["relocation/RELOCATION_DB_PASSWORD"].id
  secret_string = random_password.rds_master.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}
