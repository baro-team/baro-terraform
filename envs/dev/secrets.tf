resource "aws_secretsmanager_secret" "service" {
  for_each = local.secret_keys

  name                    = "${local.name_prefix}/${each.value}"
  recovery_window_in_days = 0
}
