# ComfySpotMgr - Data Sources
# Data sources for dynamic resource selection

# Get the latest Deep Learning VM image with CUDA 12.3
data "google_compute_image" "deep_learning_image" {
  family  = "common-cu123"
  project = "ml-images"
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Get available zones in the selected region
data "google_compute_zones" "available" {
  region = var.region
  status = "UP"
}