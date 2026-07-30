output "distribution_id" {
  description = "The CloudFront distribution ID."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_domain_name" {
  description = "The CloudFront distribution's domain name, for Route 53 alias records."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  description = "The CloudFront distribution's hosted zone ID, for Route 53 alias records."
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "oai_iam_arn" {
  description = "IAM ARN of the Origin Access Identity, for modules/static-site-bucket's oai_iam_arn."
  value       = aws_cloudfront_origin_access_identity.this.iam_arn
}
