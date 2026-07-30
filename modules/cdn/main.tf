resource "aws_cloudfront_origin_access_identity" "this" {
  comment = coalesce(var.oai_comment, var.comment)
}

# Viewer-request function that appends index.html for directory-style
# request URIs — the fix for the 403 documented in meltan.ca#27.
resource "aws_cloudfront_function" "append_index_html" {
  name    = var.function_name
  runtime = "cloudfront-js-2.0"
  comment = "Append index.html for directory-style requests"
  publish = true

  code = <<-EOT
    function handler(event) {
        var request = event.request;
        var uri = request.uri;

        if (uri.endsWith('/')) {
            request.uri += 'index.html';
        } else if (!uri.includes('.')) {
            request.uri += '/index.html';
        }

        return request;
    }
  EOT

  # publish is a write-only directive (AWS doesn't return it as a readable
  # attribute), so it always shows a phantom diff right after import
  # regardless of what's set here. Applying it is harmless -- it just
  # re-publishes code that's already live -- but there's no HCL value that
  # makes the diff go away on its own, so it's suppressed explicitly.
  lifecycle {
    ignore_changes = [publish]
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.comment
  aliases             = var.aliases
  price_class         = var.price_class
  default_root_object = var.default_root_object
  tags                = var.tags

  origin {
    domain_name = var.origin_domain_name
    origin_id   = var.origin_domain_name

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.this.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.origin_domain_name
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.append_index_html.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
