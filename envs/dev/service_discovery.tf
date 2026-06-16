resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "baro.internal"
  description = "Private DNS namespace for baro services"
  vpc         = aws_vpc.this.id
}

resource "aws_service_discovery_service" "kafka" {
  name = "kafka"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "WEIGHTED"
  }
}

resource "aws_service_discovery_instance" "kafka" {
  count = var.runtime_enabled ? 1 : 0

  instance_id = one(aws_instance.kafka[*].id)
  service_id  = aws_service_discovery_service.kafka.id

  attributes = {
    AWS_INSTANCE_IPV4 = one(aws_instance.kafka[*].private_ip)
  }
}

resource "aws_service_discovery_service" "service" {
  for_each = local.runtime_services

  name = each.value.module

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
