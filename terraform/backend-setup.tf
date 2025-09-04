# ComfySpotMgr - Backend Setup
# Run this first to create the Terraform state bucket
# Usage: terraform apply -target=google_storage_bucket.terraform_state

resource "google_storage_bucket" "terraform_state" {
  name          = var.terraform_state_bucket
  location      = var.bucket_location
  force_destroy = false

  # Enable versioning for state file backup
  versioning {
    enabled = true
  }

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  # Enable object-level access control
  uniform_bucket_level_access = true

  # Use default Google-managed encryption
  # encryption block is optional - Google manages encryption by default
}

# Grant Terraform service permissions to the state bucket
resource "google_storage_bucket_iam_member" "terraform_state_access" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.admin"
  member = "user:${var.iap_user_email}" # Replace with your Terraform runner email
}