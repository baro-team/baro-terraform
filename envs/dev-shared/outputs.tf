output "name_prefix" {
  description = "Common resource name prefix."
  value       = local.name_prefix
}

output "vpc_id" {
  description = "Shared VPC ID."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "ecr_repository_urls" {
  description = "ECR repository URLs by service key."
  value       = { for key, repo in aws_ecr_repository.service : key => repo.repository_url }
}

output "service_secret_arns" {
  description = "Service secret ARNs by service/secret key."
  value       = { for key, secret in aws_secretsmanager_secret.service : key => secret.arn }
}

output "service_secret_ids" {
  description = "Service secret IDs by service/secret key."
  value       = { for key, secret in aws_secretsmanager_secret.service : key => secret.id }
}

output "secret_names" {
  description = "Secrets to populate before running tasks."
  value       = [for secret in aws_secretsmanager_secret.service : secret.name]
}
