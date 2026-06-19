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
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }

  # templatefile() 사용: <<-USERDATA 헤레독은 앞 공백을 제거하지 않아 #!/bin/bash가
  # 컬럼 0에 위치하지 않으면 cloud-init이 스크립트로 인식하지 못함
  user_data_base64 = base64encode(templatefile("${path.module}/mosquitto-userdata.sh.tpl", {
    secret_arn = aws_secretsmanager_secret.mosquitto_credentials.arn
    region     = var.aws_region
  }))

  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mosquitto"
  })
}
