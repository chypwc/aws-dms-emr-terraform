terraform {
  required_version = "1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }

  }

  backend "s3" {
    bucket = "terraform-chien"
    key    = "dev/terraform.tfstate"
    region = "ap-southeast-2"
    # dynamodb_table = "terraform-lock-table" //  state locking, prevents concurrent modifications to the state file
    encrypt = true
  }
}

provider "aws" {
  region = var.region
}


