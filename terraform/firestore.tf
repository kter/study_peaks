# Enable Firestore API
resource "google_project_service" "firestore" {
  project            = var.project_id
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

# Firestore Database in Native Mode
resource "google_firestore_database" "main" {
  provider = google-beta
  project  = var.project_id
  name     = "(default)"

  location_id                 = var.region
  type                        = "FIRESTORE_NATIVE"
  concurrency_mode            = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"

  # Use ABANDON in production to prevent accidental data loss
  deletion_policy = local.config.deletion_protection ? "ABANDON" : "DELETE"

  depends_on = [google_project_service.firestore]
}

resource "google_firestore_field" "seats_user_id" {
  project    = var.project_id
  database   = google_firestore_database.main.name
  collection = "seats"
  field      = "userId"

  index_config {
    indexes {
      order       = "ASCENDING"
      query_scope = "COLLECTION_GROUP"
    }
    indexes {
      order       = "ASCENDING"
      query_scope = "COLLECTION"
    }
    indexes {
      order       = "DESCENDING"
      query_scope = "COLLECTION"
    }
    indexes {
      array_config = "CONTAINS"
      query_scope  = "COLLECTION"
    }
  }
}

# Firestore Security Rules
# Note: Security rules must be deployed via gcloud or CI/CD
# terraform does not fully support firestore rules deployment
