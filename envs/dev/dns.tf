data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "alb" {
  domain_name               = local.app_domain_name
  subject_alternative_names = concat(["internal-${local.app_domain_name}"], [for _, config in local.service_metrics_rules : config.host])
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = local.app_domain_name
  }
}

resource "aws_route53_record" "alb_certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.alb.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in aws_route53_record.alb_certificate_validation : record.fqdn]
}

resource "aws_route53_record" "app" {
  count = var.runtime_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.app_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "internal_app" {
  count   = var.runtime_enabled ? 1 : 0
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "internal-${local.app_domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.internal[0].dns_name
    zone_id                = aws_lb.internal[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "service_metrics" {
  for_each = var.runtime_enabled ? local.service_metrics_hosts : {}

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.internal[0].dns_name
    zone_id                = aws_lb.internal[0].zone_id
    evaluate_target_health = true
  }
}
