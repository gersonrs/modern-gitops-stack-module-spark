terraform {
  required_version = ">= 1.9.0"

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.18"
    }
    utils = {
      source  = "cloudposse/utils"
      version = "~> 2.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3"
    }
  }
}
