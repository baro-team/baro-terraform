output "alb_dns_name" {
  description = "Public ALB DNS name."
  value       = var.runtime_enabled ? aws_lb.this[0].dns_name : null
}

output "app_domain_name" {
  description = "Stable dev application domain name."
  value       = local.app_domain_name
}

output "app_url" {
  description = "Stable HTTPS dev application URL."
  value       = "https://${local.app_domain_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = var.runtime_enabled ? aws_ecs_cluster.this[0].name : null
}

output "ecr_repository_urls" {
  description = "ECR repository URLs by service key."
  value       = { for key, repo in aws_ecr_repository.service : key => repo.repository_url }
}

output "internal_alb_url" {
  description = "Fixed DNS name for the Internal ALB. Use this in Airflow."
  value       = var.runtime_enabled ? "https://${aws_route53_record.internal_app[0].name}" : ""
}

output "secret_names" {
  description = "Secrets to populate before running tasks."
  value       = [for secret in aws_secretsmanager_secret.service : secret.name]
}

output "rds_endpoint" {
  description = "Private RDS PostgreSQL endpoint."
  value       = var.runtime_enabled ? aws_db_instance.postgres[0].endpoint : null
}

output "rds_database_name" {
  description = "Shared PostgreSQL database name."
  value       = var.runtime_enabled ? aws_db_instance.postgres[0].db_name : null
}

output "rds_master_secret_name" {
  description = "Secrets Manager name containing generated RDS master credentials."
  value       = aws_secretsmanager_secret.rds_master.name
}

output "user_service_jdbc_url" {
  description = "User service JDBC URL with currentSchema=user_service."
  value       = var.runtime_enabled ? "jdbc:postgresql://${aws_db_instance.postgres[0].address}:${aws_db_instance.postgres[0].port}/${aws_db_instance.postgres[0].db_name}?currentSchema=user_service" : null
}

output "dispatch_service_jdbc_url" {
  description = "Dispatch service JDBC URL with currentSchema=dispatch_service."
  value       = var.runtime_enabled ? "jdbc:postgresql://${aws_db_instance.postgres[0].address}:${aws_db_instance.postgres[0].port}/${aws_db_instance.postgres[0].db_name}?currentSchema=dispatch_service" : null
}

output "db_init_task_definition_arn" {
  description = "Run this one-off ECS task after apply to create PostgreSQL schemas."
  value       = var.runtime_enabled ? aws_ecs_task_definition.db_init[0].arn : null
}

output "private_subnet_ids" {
  description = "Private subnet IDs for running one-off ECS tasks."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks."
  value       = aws_security_group.ecs_tasks.id
}

output "redis_host" {
  description = "ElastiCache Valkey endpoint for vehicle GEO cache."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "ElastiCache Valkey port for vehicle GEO cache."
  value       = aws_elasticache_replication_group.redis.port
}
