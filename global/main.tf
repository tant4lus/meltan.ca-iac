resource "aws_route53_zone" "this" {
  name    = "meltan.ca"
  comment = ""

  tags = {
    company = "personal"
  }
}

# Google Workspace mail.
resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "meltan.ca"
  type    = "MX"
  ttl     = 604800

  records = [
    "10 aspmx.l.google.com.",
    "20 alt1.aspmx.l.google.com.",
    "30 alt2.aspmx.l.google.com.",
    "40 aspmx2.googlemail.com.",
    "50 aspmx3.googlemail.com.",
  ]
}

# Google Search Console site verification.
resource "aws_route53_record" "site_verification" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "meltan.ca"
  type    = "TXT"
  ttl     = 3600

  records = [
    "google-site-verification=rvRDw8_I525KnRnfjB5pTeGd8QsOfWs8KtjOLk-IgbY",
  ]
}
