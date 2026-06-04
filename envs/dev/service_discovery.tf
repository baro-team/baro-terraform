resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "baro.internal"
  description = "Private DNS namespace for baro services"
  vpc         = aws_vpc.this.id
}

