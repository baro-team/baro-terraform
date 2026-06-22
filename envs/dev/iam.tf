data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution_secrets" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "kms:Decrypt"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name   = "${local.name_prefix}-ecs-task-execution-secrets"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_execution_secrets.json
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# ── GitHub Actions: baro-edge EC2 SSM 배포 권한 ──────────────────────────────
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY 를 사용하는 IAM 유저에 attach 필요
# e.g. aws iam attach-user-policy --user-name <github-actions-user> \
#        --policy-arn <아래 policy arn>

data "aws_iam_policy_document" "github_actions_baro_edge" {
  statement {
    sid       = "EC2Describe"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid = "SSMSendCommand"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}:*:instance/*",
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
    ]
  }
}

resource "aws_iam_policy" "github_actions_baro_edge" {
  name   = "${local.name_prefix}-github-actions-baro-edge"
  policy = data.aws_iam_policy_document.github_actions_baro_edge.json
}

output "github_actions_baro_edge_policy_arn" {
  description = "IAM 정책 ARN — GitHub Actions IAM 유저에 attach 필요 (baro-edge SSM 배포용)"
  value       = aws_iam_policy.github_actions_baro_edge.arn
}
