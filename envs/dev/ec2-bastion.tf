data "aws_ami" "amazon_linux_2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-kernel-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_policy_document" "bastion_ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion_ec2" {
  name               = "${local.name_prefix}-bastion-ec2"
  assume_role_policy = data.aws_iam_policy_document.bastion_ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "bastion_ec2_ssm" {
  role       = aws_iam_role.bastion_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_ec2" {
  name = "${local.name_prefix}-bastion-ec2"
  role = aws_iam_role.bastion_ec2.name
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023_arm64.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.private["0"].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2.name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bastion"
  })
}
