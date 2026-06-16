data "aws_ecr_repository" "baro_edge" {
  name = "${var.project}-baro-edge"
}

# ── IAM ──────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "mosquitto_ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mosquitto_ec2" {
  name               = "${local.name_prefix}-mosquitto-ec2"
  assume_role_policy = data.aws_iam_policy_document.mosquitto_ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mosquitto_ec2_ssm" {
  role       = aws_iam_role.mosquitto_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "mosquitto_ec2_ecr" {
  role       = aws_iam_role.mosquitto_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "mosquitto_ec2" {
  name = "${local.name_prefix}-mosquitto-ec2"
  role = aws_iam_role.mosquitto_ec2.name
}

# ── EC2 ──────────────────────────────────────────────────────────────────────

resource "aws_instance" "mosquitto" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = values(aws_subnet.private)[0].id
  vpc_security_group_ids = [aws_security_group.mosquitto.id]
  iam_instance_profile   = aws_iam_instance_profile.mosquitto_ec2.name
  private_ip             = "10.20.10.32"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker

    # Docker 브리지 네트워크 생성 (컨테이너 간 이름으로 통신)
    docker network create baro-edge-net

    # mosquitto.conf 생성
    mkdir -p /opt/mosquitto/data
    cat > /opt/mosquitto/mosquitto.conf <<'EOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest stdout
log_type error
log_type warning
log_type notice
EOF

    # Mosquitto 2.x 실행 ($share 구독 지원)
    docker run -d --name mosquitto \
      --network baro-edge-net \
      --restart unless-stopped \
      -p 1883:1883 \
      -v /opt/mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf \
      -v /opt/mosquitto/data:/mosquitto/data \
      eclipse-mosquitto:2

    # ECR 로그인 후 baro-edge 실행
    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin ${data.aws_ecr_repository.baro_edge.repository_url}

    docker run -d --name baro-edge \
      --network baro-edge-net \
      --restart unless-stopped \
      -e MQTT_BROKER_HOST=mosquitto \
      -e MQTT_BROKER_PORT=1883 \
      ${data.aws_ecr_repository.baro_edge.repository_url}:${var.image_tag}
    USERDATA
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mosquitto"
  })
}
