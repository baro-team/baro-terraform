resource "aws_secretsmanager_secret" "service" {
  for_each = local.secret_keys

  name                    = "${local.name_prefix}/${each.value}"
  recovery_window_in_days = 0
}

data "aws_secretsmanager_secret" "internal_api_key" {
  name = var.internal_api_key_secret_name
}
