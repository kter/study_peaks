# Enable required APIs
resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "scheduler" {
  project            = var.project_id
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

# Cloud Run Service for Backend API
resource "google_cloud_run_v2_service" "api" {
  name     = "study-peaks-api-${local.environment}"
  location = var.region
  
  depends_on = [
    google_project_service.run,
    google_artifact_registry_repository.api,
  ]

  template {
    containers {
      # Use placeholder image for initial deployment, update after API is built
      image = local.api_image

      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }

      env {
        name  = "ENVIRONMENT"
        value = local.environment
      }

      resources {
        limits = {
          cpu    = local.environment == "prd" ? "2" : "1"
          memory = local.environment == "prd" ? "1Gi" : "512Mi"
        }
        cpu_idle = local.environment != "prd"
      }

      startup_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 0
        period_seconds        = 10
        failure_threshold     = 3
      }
    }

    scaling {
      min_instance_count = local.config.min_instances
      max_instance_count = local.config.max_instances
    }

    service_account = google_service_account.api.email
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Service Account for Cloud Run
resource "google_service_account" "api" {
  account_id   = "study-peaks-api-${local.environment}"
  display_name = "Study Peaks API Service Account (${local.environment})"
  project      = var.project_id
}

# Grant Firestore access to the service account
resource "google_project_iam_member" "api_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Allow unauthenticated access (for public API endpoints)
# In production, consider removing this and using IAP or other auth
resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Scheduler for auto-logout (24h inactive sessions)
resource "google_cloud_scheduler_job" "auto_logout" {
  name        = "study-peaks-auto-logout-${local.environment}"
  description = "Force logout inactive sessions (24h without activity)"
  schedule    = "0 * * * *" # Every hour
  time_zone   = "UTC"
  region      = var.region

  depends_on = [google_project_service.scheduler]

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.api.uri}/internal/cleanup-sessions"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Service Account for Cloud Scheduler
resource "google_service_account" "scheduler" {
  account_id   = "study-peaks-scheduler-${local.environment}"
  display_name = "Study Peaks Scheduler Service Account (${local.environment})"
  project      = var.project_id
}

# Grant Cloud Run invoker role to scheduler
resource "google_cloud_run_v2_service_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}
