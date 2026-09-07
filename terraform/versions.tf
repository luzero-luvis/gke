terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.17.0, < 8.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.17.0, < 8.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.38.0, < 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

