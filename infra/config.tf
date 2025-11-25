variable "project_id" {
  type = string
}
variable "project_number" {
  type = number
}
variable "domain" {
  type = string
}

locals {
  project_id             = var.project_id
  project_number         = var.project_number
  project_default_region = "europe-west1"
  project_default_zone   = "europe-west1-a"
}

terraform {
  required_version = ">= 1.13"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "= 2.6.0"
    }

    google = {
      source  = "hashicorp/google"
      version = "= 7.12.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "= 7.12.0"
    }
  }
}

