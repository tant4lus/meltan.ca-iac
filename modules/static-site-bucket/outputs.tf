output "bucket_id" {
  description = "The bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "The bucket's regional domain name, for use as a CloudFront origin."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "website_endpoint" {
  description = "The S3 website-hosting endpoint. Only set when mode is \"public\"."
  value       = try(aws_s3_bucket_website_configuration.this[0].website_endpoint, null)
}
