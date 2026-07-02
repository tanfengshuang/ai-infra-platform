# ============================================================
# providers.tf — AWS + GitHub 双 Provider
# ============================================================
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket = "ai-log-agent-tfstate"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "github" {
  token = var.github_token
  owner = "tanfengshuang"
}
