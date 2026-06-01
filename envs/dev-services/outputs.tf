output "alb_dns_name" {
  description = "Public ALB DNS name."
  value       = aws_lb.this.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "rds_endpoint" {
  description = "Private RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "rds_database_name" {
  description = "Shared PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "rds_master_secret_name" {
  description = "Secrets Manager name containing generated RDS master credentials."
  value       = aws_secretsmanager_secret.rds_master.name
}

output "user_service_jdbc_url" {
  description = "JDBC URL you can put into baro-dev/user/USER_DB_URL. Add currentSchema if your app migrations use schemas."
  value       = "jdbc:postgresql://${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}?currentSchema=user_service"
}

output "dispatch_service_jdbc_url" {
  description = "JDBC URL automatically stored in baro-dev/dispatch/DISPATCH_DB_URL."
  value       = "jdbc:postgresql://${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}?currentSchema=dispatch_service"
}

output "db_init_task_definition_arn" {
  description = "Run this one-off ECS task after apply to create PostgreSQL schemas."
  value       = aws_ecs_task_definition.db_init.arn
}

output "private_subnet_ids" {
  description = "Private subnet IDs for running one-off ECS tasks."
  value       = local.shared.private_subnet_ids
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks."
  value       = aws_security_group.ecs_tasks.id
}
