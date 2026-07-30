# The meltan.ca hosted zone, managed in the meltan-ca-global workspace.
# Hardcoded rather than looked up by name: a route53:ListHostedZones lookup
# can't be IAM-scoped to a single zone, and this ID is already public
# information (it's not a secret), same as prod's hardcoded OAI ARN in
# environments/prod/main.tf.
locals {
  hosted_zone_id = "Z038765422KUTVSCFJIK2"
}

resource "aws_acm_certificate" "this" {
  provider          = aws.us_east_1
  domain_name       = "stage.meltan.ca"
  validation_method = "DNS"

  tags = {
    company = "personal"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = local.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "this" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

module "bucket" {
  source = "../../modules/static-site-bucket"

  bucket_name = "meltan.ca-staging"
  mode        = "oai"
  oai_iam_arn = module.cdn.oai_iam_arn

  tags = {
    company = "personal"
  }
}

module "cdn" {
  source = "../../modules/cdn"

  origin_domain_name  = module.bucket.bucket_regional_domain_name
  function_name       = "append-index-html-stage"
  aliases             = ["stage.meltan.ca"]
  acm_certificate_arn = aws_acm_certificate_validation.this.certificate_arn
  comment             = "stage.meltan.ca"
  default_root_object = "index.html"

  tags = {
    company = "personal"
  }
}

resource "aws_route53_record" "stage" {
  zone_id = local.hosted_zone_id
  name    = "stage.meltan.ca"
  type    = "A"

  alias {
    name                   = module.cdn.distribution_domain_name
    zone_id                = module.cdn.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}
