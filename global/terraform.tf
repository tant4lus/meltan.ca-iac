terraform {
  cloud {
    organization = "meltan"
    workspaces {
      name = "meltan-ca-global"
    }
  }

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
