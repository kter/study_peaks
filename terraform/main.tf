# Terraform Workspace Configuration
#
# This configuration uses Terraform workspaces to manage multiple environments.
#
# Usage:
#   terraform workspace new dev
#   terraform workspace new prd
#   terraform workspace select dev
#   terraform apply -var-file="env/dev.tfvars"
#
#   terraform workspace select prd
#   terraform apply -var-file="env/prd.tfvars"

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure for remote state
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "study-peaks"
  # }
}

# Local values derived from workspace
locals {
  # Map workspace name to environment
  environment = terraform.workspace == "default" ? "dev" : terraform.workspace
  
  # Environment-specific configurations
  env_config = {
    dev = {
      min_instances = 0
      max_instances = 5
      deletion_protection = false
    }
    prd = {
      min_instances = 1
      max_instances = 20
      deletion_protection = true
    }
  }
  
  # Get current environment config (default to dev if workspace not found)
  config = lookup(local.env_config, local.environment, local.env_config["dev"])

  # API image URL - uses placeholder for initial deploy, then Artifact Registry
  # After first deploy, push your image to: ${var.region}-docker.pkg.dev/${var.project_id}/study-peaks/api:latest
  api_image = var.api_image != "" ? var.api_image : "gcr.io/cloudrun/hello"
}

provider "google" {
  project                     = var.project_id
  region                      = var.region
  user_project_override       = true
  billing_project             = var.project_id
}

provider "google-beta" {
  project                     = var.project_id
  region                      = var.region
  user_project_override       = true
  billing_project             = var.project_id
}
