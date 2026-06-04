resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = local.common_tags
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${local.name_prefix}-valkey"
  description                = "Valkey cache for dispatchable vehicle GEO data"
  engine                     = "valkey"
  engine_version             = "7.2"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  parameter_group_name       = "default.valkey7"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]

  tags = local.common_tags
}
