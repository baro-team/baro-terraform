resource "aws_ecr_repository" "baro_edge" {
  name                 = "${local.name_prefix}-baro-edge"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "baro_edge" {
  repository = aws_ecr_repository.baro_edge.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ── MQTT 자격증명 ─────────────────────────────────────────────────────────────

resource "random_password" "mosquitto_mqtt" {
  length           = 32
  special          = true
  override_special = "!#%&*()-_=+[]<>:?"
}

resource "aws_secretsmanager_secret" "mosquitto_credentials" {
  name                    = "${local.name_prefix}/mosquitto/credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mosquitto_credentials" {
  secret_id = aws_secretsmanager_secret.mosquitto_credentials.id
  secret_string = jsonencode({
    username = "mqtt_user"
    password = random_password.mosquitto_mqtt.result
  })
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

data "aws_iam_policy_document" "mosquitto_ec2_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.mosquitto_credentials.arn]
  }
}

resource "aws_iam_role_policy" "mosquitto_ec2_secrets" {
  name   = "mosquitto-credentials"
  role   = aws_iam_role.mosquitto_ec2.name
  policy = data.aws_iam_policy_document.mosquitto_ec2_secrets.json
}

resource "aws_iam_instance_profile" "mosquitto_ec2" {
  name = "${local.name_prefix}-mosquitto-ec2"
  role = aws_iam_role.mosquitto_ec2.name
}

# ── EC2 ──────────────────────────────────────────────────────────────────────

resource "aws_instance" "mosquitto" {
  count = var.runtime_enabled ? 1 : 0

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = values(aws_subnet.private)[0].id
  vpc_security_group_ids = [aws_security_group.mosquitto.id]
  iam_instance_profile   = aws_iam_instance_profile.mosquitto_ec2.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker

    # Docker 브리지 네트워크 생성 (컨테이너 간 이름으로 통신)
    docker network create baro-edge-net

    # Secrets Manager에서 MQTT 자격증명 가져오기
    MQTT_SECRET=$(aws secretsmanager get-secret-value \
      --secret-id "${aws_secretsmanager_secret.mosquitto_credentials.arn}" \
      --region ${var.aws_region} \
      --query SecretString \
      --output text)
    MQTT_USER=$(echo "$MQTT_SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
    MQTT_PASS=$(echo "$MQTT_SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

    # Mosquitto 설정 파일 생성
    mkdir -p /opt/mosquitto/config /opt/mosquitto/data

    cat > /opt/mosquitto/config/mosquitto.conf <<'EOF'
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest stdout
log_type error
log_type warning
log_type notice
EOF

    # passwd 파일 생성 (mosquitto_passwd 도구 사용)
    docker run --rm \
      -v /opt/mosquitto/config:/etc/mosquitto \
      eclipse-mosquitto:2 \
      mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USER" "$MQTT_PASS"

    chmod 600 /opt/mosquitto/config/passwd

    # Mosquitto 2.x 실행 ($share 구독 지원)
    docker run -d --name mosquitto \
      --network baro-edge-net \
      --restart unless-stopped \
      -p 1883:1883 \
      -v /opt/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
      -v /opt/mosquitto/config/passwd:/mosquitto/config/passwd \
      -v /opt/mosquitto/data:/mosquitto/data \
      eclipse-mosquitto:2

    # baro-edge는 GitHub Actions CI/CD (SSM send-command)로 배포됨
    USERDATA
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mosquitto"
  })
}
