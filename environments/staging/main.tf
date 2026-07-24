module "bucket" {
  source = "../../modules/static-site-bucket"

  bucket_name    = "meltan.ca-staging"
  mode           = "public"
  index_document = "index.html"
  error_document = "error.html"

  tags = {
    company = "personal"
  }
}
