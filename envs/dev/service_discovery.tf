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
  instance_id = aws_instance.kafka.id
  service_id  = aws_service_discovery_service.kafka.id

  attributes = {
    AWS_INSTANCE_IPV4 = aws_instance.kafka.private_ip
  }
}

