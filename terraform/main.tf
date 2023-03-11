terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "webserver" {
  source = "./modules/webserver"

  cluster_name           = var.cluster_name

  instance_type        = "t2.micro"
  min_size             = 1
  max_size             = 2
  enable_autoscaling   = false
}
