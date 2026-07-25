module "bucket" {
  source = "../../modules/static-site-bucket"

  bucket_name = "meltan.ca"
  mode        = "oai"
  oai_iam_arn = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E3OPL65VOOE078"

  tags = {
    company = "personal"
  }
}
