data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── IAM ──────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "kafka_ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kafka_ec2" {
  name               = "${local.name_prefix}-kafka-ec2"
  assume_role_policy = data.aws_iam_policy_document.kafka_ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "kafka_ec2_ssm" {
  role       = aws_iam_role.kafka_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "kafka_ec2_ecr" {
  role       = aws_iam_role.kafka_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "kafka_ec2" {
  name = "${local.name_prefix}-kafka-ec2"
  role = aws_iam_role.kafka_ec2.name
}

# ── EBS (인스턴스와 분리 관리 — 재생성 시 데이터 유지) ───────────────────────

resource "aws_ebs_volume" "kafka_data" {
  availability_zone = aws_subnet.private["0"].availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kafka-data"
  })
}

resource "aws_volume_attachment" "kafka_data" {
  count = var.runtime_enabled ? 1 : 0

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.kafka_data.id
  instance_id = one(aws_instance.kafka[*].id)
}

# ── EC2 ──────────────────────────────────────────────────────────────────────

resource "aws_instance" "kafka" {
  count = var.runtime_enabled ? 1 : 0

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.private["0"].id
  vpc_security_group_ids = [aws_security_group.kafka.id]
  iam_instance_profile   = aws_iam_instance_profile.kafka_ec2.name
  private_ip             = "10.20.10.31"

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  # templatefile() 사용: <<-USERDATA 헤레독은 앞 공백을 제거하지 않아 #!/bin/bash가
  # 컬럼 0에 위치하지 않으면 cloud-init이 스크립트로 인식하지 못함
  user_data_base64 = base64encode(templatefile("${path.module}/kafka-userdata.sh.tpl", {
    aws_region    = var.aws_region
    ecr_url       = data.aws_ecr_repository.kafka.repository_url
    image_tag     = var.image_tag
    dns_namespace = aws_service_discovery_private_dns_namespace.this.name
  }))

  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kafka"
  })
}
