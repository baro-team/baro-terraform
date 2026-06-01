resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.shared.public_subnet_ids[0]

  tags = {
    Name = local.name_prefix
  }
}

resource "aws_route_table" "private" {
  vpc_id = local.shared.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-private"
  }
}

resource "aws_route_table_association" "private" {
  for_each = { for index, subnet_id in local.shared.private_subnet_ids : index => subnet_id }

  subnet_id      = each.value
  route_table_id = aws_route_table.private.id
}

# 기존 온프레미스 Customer Gateway (112.218.95.58) 참조
data "aws_customer_gateway" "onprem" {
  filter {
    name   = "ip-address"
    values = ["112.218.95.58"]
  }
}

# baro-dev VPC에 VPN Gateway 생성
resource "aws_vpn_gateway" "this" {
  vpc_id = local.shared.vpc_id

  tags = {
    Name = "${local.name_prefix}-vgw"
  }
}

# Site-to-Site VPN 연결
resource "aws_vpn_connection" "onprem" {
  vpn_gateway_id      = aws_vpn_gateway.this.id
  customer_gateway_id = data.aws_customer_gateway.onprem.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = {
    Name = "${local.name_prefix}-vpn"
  }
}

# 온프레미스 네트워크 대역 → VPN으로 라우팅
resource "aws_vpn_connection_route" "onprem" {
  vpn_connection_id      = aws_vpn_connection.onprem.id
  destination_cidr_block = var.onprem_cidr
}

# private 서브넷 라우트 테이블에 VPN 경로 전파
resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.this.id
  route_table_id = aws_route_table.private.id
}
