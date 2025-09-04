# ComfySpotMgr - Data Sources
# Data sources for dynamic resource selection

# Local values for efficient image selection
locals {
  # Build specific family patterns to try (most recent first)
  candidate_families = [
    # Try specific newer patterns first (most likely to exist)
    "pytorch-2-7-${var.cuda_version}-${var.ubuntu_version}-nvidia-570",
    "pytorch-2-6-${var.cuda_version}-${var.ubuntu_version}-nvidia-570", 
    "pytorch-2-5-${var.cuda_version}-${var.ubuntu_version}-nvidia-570",
    # Try with different driver versions
    "pytorch-2-7-${var.cuda_version}-${var.ubuntu_version}-nvidia-535",
    "pytorch-2-6-${var.cuda_version}-${var.ubuntu_version}-nvidia-535",
    # Generic fallback patterns
    var.fallback_image_family,
    "pytorch-latest-gpu"
  ]
}

# Try the first candidate family (most likely to exist and be recent)
data "google_compute_image" "primary_candidate" {
  count   = 1
  family  = local.candidate_families[0]
  project = "deeplearning-platform-release"
  
  # This will fail silently if the family doesn't exist
  lifecycle {
    postcondition {
      condition     = self.family != null
      error_message = "Primary candidate image family '${local.candidate_families[0]}' not found, will try fallback."
    }
  }
}

# Fallback candidates in order of preference
data "google_compute_image" "fallback_candidates" {
  count   = length(local.candidate_families) - 1
  family  = local.candidate_families[count.index + 1]
  project = "deeplearning-platform-release"
}

# Select the first available image (primary or first available fallback)
locals {
  # Try primary first, then fallbacks until we find one that exists
  selected_image = try(
    data.google_compute_image.primary_candidate[0],
    data.google_compute_image.fallback_candidates[0],
    data.google_compute_image.fallback_candidates[1],
    data.google_compute_image.fallback_candidates[2],
    data.google_compute_image.fallback_candidates[3],
    data.google_compute_image.fallback_candidates[4],
    data.google_compute_image.fallback_candidates[5]
  )
  
  # Track which image was selected for outputs
  selected_family = local.selected_image.family
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
