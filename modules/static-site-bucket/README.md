# static-site-bucket

S3 bucket for a static site, in one of two modes:

- **`public`** — public-read bucket policy, used directly via the S3 website-hosting endpoint (staging today).
- **`oai`** — private bucket, `GetObject` restricted to a CloudFront Origin Access Identity (prod today, staging once it gets its own CloudFront distribution).

Covers: bucket resource, versioning, default encryption, public-access-block, ownership controls, tagging, and the bucket policy for whichever mode is selected.
