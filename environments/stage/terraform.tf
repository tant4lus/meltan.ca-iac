terraform {
  # cloud {
  #   organization = "<your-tfc-org>"
  #   workspaces {
  #     name = "meltan-ca-stage"
  #   }
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# ACM certificates for CloudFront must be requested in us-east-1, regardless
# of where the rest of the stack lives.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
