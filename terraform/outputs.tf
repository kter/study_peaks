output "environment" {
  description = "Current environment (from workspace)"
  value       = local.environment
}

output "api_url" {
  description = "Cloud Run API service URL"
  value       = google_cloud_run_v2_service.api.uri
}

output "api_service_account" {
  description = "API Service Account email"
  value       = google_service_account.api.email
}

output "firestore_database" {
  description = "Firestore database name"
  value       = google_firestore_database.main.name
}

output "scaling_config" {
  description = "Current scaling configuration"
  value = {
    min_instances       = local.config.min_instances
    max_instances       = local.config.max_instances
    deletion_protection = local.config.deletion_protection
  }
}
