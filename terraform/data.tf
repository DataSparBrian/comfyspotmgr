# ComfySpotMgr - Data Sources
# Data sources for dynamic resource selection

# Get the latest PyTorch Deep Learning VM image with GPU support
data "google_compute_image" "deep_learning_image" {
  family  = "pytorch-2-7-cu128-ubuntu-2204-nvidia-570"
  project = "deeplearning-platform-release"
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
