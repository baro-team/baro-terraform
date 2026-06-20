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
  availability_zone = values(aws_subnet.private)[0].availability_zone
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
  subnet_id              = values(aws_subnet.private)[0].id
  vpc_security_group_ids = [aws_security_group.kafka.id]
  iam_instance_profile   = aws_iam_instance_profile.kafka_ec2.name
  private_ip             = "10.20.10.31"

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker

    # aws_volume_attachment는 비동기로 붙으므로 디바이스가 준비될 때까지 대기
    while [ ! -b /dev/nvme1n1 ]; do
      echo "Waiting for /dev/nvme1n1 to be attached..."
      sleep 5
    done

    if ! blkid /dev/nvme1n1; then
      mkfs.ext4 /dev/nvme1n1
    fi
    mkdir -p /var/kafka-data
    mount /dev/nvme1n1 /var/kafka-data
    echo '/dev/nvme1n1 /var/kafka-data ext4 defaults,nofail 0 2' >> /etc/fstab
    chown 1000:1000 /var/kafka-data

    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin ${data.aws_ecr_repository.kafka.repository_url}

    docker run -d --name kafka --restart unless-stopped \
      --entrypoint /etc/confluent/docker/run \
      -p 9092:9092 \
      -p 9093:9093 \
      -v /var/kafka-data:/var/kafka-data \
      -e KAFKA_NODE_ID=1 \
      -e KAFKA_PROCESS_ROLES=broker,controller \
      -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
      -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka.${aws_service_discovery_private_dns_namespace.this.name}:9092 \
      -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT \
      -e KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT \
      -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
      -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
      -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
      -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
      -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
      -e CLUSTER_ID=MkU3OEVBNTcwNTJENDM2Qk \
      -e KAFKA_LOG_DIRS=/var/kafka-data \
      -e KAFKA_HEAP_OPTS="-Xms256M -Xmx512M" \
      ${data.aws_ecr_repository.kafka.repository_url}:${var.image_tag}

    echo "[$(date -u)] Waiting for Kafka to be ready..."
    until docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list >/dev/null 2>&1; do
      sleep 5
    done

    echo "[$(date -u)] Ensuring vehicle-data-topic has 4 partitions..."
    CURRENT_PARTS=$(docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
      --describe --topic vehicle-data-topic 2>/dev/null | grep -v "PartitionCount" | grep -c "Partition:" || true)
    if [ "$${CURRENT_PARTS:-0}" -eq 0 ]; then
      docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
        --create --topic vehicle-data-topic --partitions 4 --replication-factor 1
    elif [ "$${CURRENT_PARTS:-0}" -lt 4 ]; then
      docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
        --alter --topic vehicle-data-topic --partitions 4
    fi
    echo "[$(date -u)] vehicle-data-topic ready (partitions=$${CURRENT_PARTS:-created})"
    USERDATA
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kafka"
  })
}
