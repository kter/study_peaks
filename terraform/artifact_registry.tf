# Enable Artifact Registry API
resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "api" {
  project       = var.project_id
  location      = var.region
  repository_id = "study-peaks"
  description   = "Docker repository for Study Peaks API"
  format        = "DOCKER"

  cleanup_policy_dry_run = false

  depends_on = [google_project_service.artifactregistry]
}

# Grant Cloud Run service account permission to pull images
resource "google_artifact_registry_repository_iam_member" "api_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.api.location
  repository = google_artifact_registry_repository.api.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.api.email}"
}
