variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region for resources"
  type        = string
  default     = "asia-northeast1"
}

variable "api_image" {
  description = "Docker image for the API service"
  type        = string
  default     = "gcr.io/cloudrun/hello"
}

variable "google_oauth_client_id" {
  description = "Google OAuth Client ID for Identity Platform"
  type        = string
  default     = ""
}

variable "google_oauth_client_secret" {
  description = "Google OAuth Client Secret for Identity Platform"
  type        = string
  default     = ""
  sensitive   = true
}
