variable "bucket_name" {
  description = "S3 bucket name."
  type        = string
}

variable "mode" {
  description = "Access mode: \"public\" for a directly browsable static site served from the S3 website endpoint, or \"oai\" for a bucket restricted to a CloudFront Origin Access Identity."
  type        = string

  validation {
    condition     = contains(["public", "oai"], var.mode)
    error_message = "mode must be either \"public\" or \"oai\"."
  }
}

variable "oai_iam_arn" {
  description = "IAM ARN of the CloudFront Origin Access Identity allowed to read the bucket. Required when mode is \"oai\"."
  type        = string
  default     = null
}

variable "index_document" {
  description = "Index document for the S3 website configuration. Only used when mode is \"public\"."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for the S3 website configuration. Only used when mode is \"public\"."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the bucket."
  type        = map(string)
  default     = {}
}
