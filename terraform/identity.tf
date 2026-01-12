# Enable Identity Platform API
resource "google_project_service" "identity_platform" {
  project            = var.project_id
  service            = "identitytoolkit.googleapis.com"
  disable_on_destroy = false
}

# Identity Platform Configuration
resource "google_identity_platform_config" "main" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.identity_platform]

  # Sign-in configuration
  sign_in {
    allow_duplicate_emails = false

    anonymous {
      enabled = false
    }

    email {
      enabled           = true
      password_required = true
    }
  }

  # Blocking functions (optional, for custom auth logic)
  # blocking_functions {
  #   triggers {
  #     event_type   = "beforeCreate"
  #     function_uri = "https://..."
  #   }
  # }
}

# OAuth Client for Identity Platform (Web)
resource "google_identity_platform_default_supported_idp_config" "google" {
  provider       = google-beta
  project        = var.project_id
  enabled        = true
  idp_id         = "google.com"
  client_id      = var.google_oauth_client_id
  client_secret  = var.google_oauth_client_secret

  depends_on = [google_identity_platform_config.main]

  count = var.google_oauth_client_id != "" ? 1 : 0
}
