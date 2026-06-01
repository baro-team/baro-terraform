resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-efs"
  description = "Allow NFS from Kafka ECS task"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "NFS from Kafka"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-efs"
  }
}

resource "aws_efs_file_system" "kafka" {
  encrypted = true

  tags = {
    Name = "${local.name_prefix}-kafka"
  }
}

resource "aws_efs_mount_target" "kafka" {
  for_each = aws_subnet.private

  file_system_id  = aws_efs_file_system.kafka.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "kafka" {
  file_system_id = aws_efs_file_system.kafka.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/kafka-data"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${local.name_prefix}-kafka"
  }
}
