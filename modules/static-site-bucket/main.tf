resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.mode == "oai"
  block_public_policy     = var.mode == "oai"
  ignore_public_acls      = var.mode == "oai"
  restrict_public_buckets = var.mode == "oai"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_website_configuration" "this" {
  count  = var.mode == "public" ? 1 : 0
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = var.index_document
  }

  dynamic "error_document" {
    for_each = var.error_document == null ? [] : [var.error_document]
    content {
      key = error_document.value
    }
  }
}

data "aws_iam_policy_document" "this" {
  policy_id = var.mode == "oai" ? "PolicyForCloudFrontPrivateContent" : null

  dynamic "statement" {
    for_each = var.mode == "public" ? [1] : []
    content {
      sid       = "PublicReadGetObject"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.mode == "oai" ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = [var.oai_iam_arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket     = aws_s3_bucket.this.id
  policy     = data.aws_iam_policy_document.this.json
  depends_on = [aws_s3_bucket_public_access_block.this]

  lifecycle {
    precondition {
      condition     = var.mode != "oai" || var.oai_iam_arn != null
      error_message = "oai_iam_arn must be set when mode is \"oai\"."
    }
  }
}
