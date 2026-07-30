variable "origin_domain_name" {
  description = "Regional domain name of the S3 bucket (oai mode) to use as the CloudFront origin."
  type        = string
}

variable "function_name" {
  description = "Name for this instantiation's directory-index CloudFront Function. Must be unique per AWS account — each instantiation owns its own copy, it isn't shared across environments."
  type        = string
}

variable "aliases" {
  description = "Alternate domain names (CNAMEs) for the distribution."
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate covering the aliases. Must be requested in us-east-1, regardless of where the rest of the stack lives."
  type        = string
}

variable "comment" {
  description = "Comment applied to the distribution and its Origin Access Identity."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Tags to apply to the distribution."
  type        = map(string)
  default     = {}
}
