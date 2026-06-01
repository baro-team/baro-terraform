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

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
