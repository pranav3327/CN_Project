terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.40" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.4" }
    http  = { source = "hashicorp/http", version = "~> 3.4" }
  }
}

# Credentials come from ~/.aws/credentials (AWS Academy: paste the block from
# "AWS Details", including aws_session_token – see: make creds).
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "cn-project", Team = var.team }
  }
}
