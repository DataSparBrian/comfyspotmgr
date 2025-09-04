# ComfySpotMgr - Data Sources
# Data sources for dynamic resource selection

# Local values for current supported Deep Learning VM image
locals {
  # Google Cloud currently supports only one PyTorch Deep Learning VM family:
  # pytorch-2-7-cu128-ubuntu-2204-nvidia-570
  # 
  # This is the current supported family as of 2024/2025
  # All other PyTorch families and TensorFlow families have been deprecated
  deep_learning_image_family = "pytorch-2-7-cu128-ubuntu-2204-nvidia-570"
}

# Get the latest image from the current supported Deep Learning VM family
data "google_compute_image" "deep_learning_vm" {
  family  = local.deep_learning_image_family
  project = "deeplearning-platform-release"
}

# For backwards compatibility and outputs
locals {
  selected_image = data.google_compute_image.deep_learning_vm
  selected_family = data.google_compute_image.deep_learning_vm.family
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
