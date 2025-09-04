# ComfySpotMgr - Main Terraform Configuration
# ComfyUI Spot Deployment Manager infrastructure

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.20.0"
    }
  }

  backend "gcs" {
    # bucket configured during terraform init
    prefix = "terraform/state"
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Local values for computed and derived values
locals {
  common_tags = [
    "comfy-ui",
    "spot-instance",
    "gpu-workload"
  ]

  # Merge user tags with common tags
  instance_tags = concat(var.tags, local.common_tags)

  # Naming convention
  resource_prefix = "${var.project_id}-comfy"

  # Common labels for resources
  common_labels = {
    project     = var.project_id
    managed_by  = "terraform"
    environment = "development"
    component   = "comfy-ui"
  }
}

# --------------------------------------------------------------------
# 1. Custom VPC Network
# --------------------------------------------------------------------
resource "google_compute_network" "comfy_net" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "comfy_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.comfy_net.id
}

# --------------------------------------------------------------------
# 2. Dedicated Service Account
# --------------------------------------------------------------------
resource "google_service_account" "comfy_sa" {
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
}

# Grant the user permission to use the service account
resource "google_service_account_iam_member" "comfy_sa_user" {
  service_account_id = google_service_account.comfy_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "user:${var.iap_user_email}"
}

# --------------------------------------------------------------------
# 3. Google Cloud Storage Bucket for Models
# --------------------------------------------------------------------
resource "google_storage_bucket" "model_storage_bucket" {
  name                        = var.bucket_name
  location                    = var.bucket_location
  force_destroy               = var.bucket_force_destroy
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "comfy_sa_gcs_permissions" {
  bucket = google_storage_bucket.model_storage_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.comfy_sa.email}"
}

# --------------------------------------------------------------------
# 4. The Spot VM Instance (Updated for GCS FUSE)
# --------------------------------------------------------------------
resource "google_compute_instance" "comfy_spot_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  # The boot disk is now smaller and can be safely deleted with the instance
  boot_disk {
    auto_delete = true
    initialize_params {
      size  = 100  # Deep Learning VM requires minimum 100 GB
      image = local.selected_image.self_link
    }
  }

  dynamic "shielded_instance_config" {
    for_each = var.enable_shielded_vm ? [1] : []
    content {
      enable_secure_boot          = var.enable_secure_boot
      enable_vtpm                 = var.enable_vtpm
      enable_integrity_monitoring = var.enable_integrity_monitoring
    }
  }

  service_account {
    email  = google_service_account.comfy_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  guest_accelerator {
    type  = var.gpu_type
    count = var.gpu_count
  }

  scheduling {
    preemptible                 = true
    provisioning_model          = "SPOT"
    automatic_restart          = false
    instance_termination_action = "DELETE"
    on_host_maintenance         = "TERMINATE"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.comfy_subnet.id
    access_config {
      # Ephemeral public IP
    }
  }

  # UPDATED - Startup script now installs FUSE and mounts the GCS bucket
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    
    # Variables
    USER_HOME=$(eval echo ~$(logname))
    GCS_BUCKET_NAME="${google_storage_bucket.model_storage_bucket.name}"
    GCS_MOUNT_DIR="$USER_HOME/gcs_models"
    RAM_DISK_SIZE="${var.ram_disk_size}"
    RAM_DISK_PATH="/mnt/ramdisk"
    COMFY_PATH="$RAM_DISK_PATH/ComfyUI"
    MODELS_PATH="$RAM_DISK_PATH/models"

    # Install dependencies
    export GCSFUSE_REPO=gcsfuse-$(lsb_release -c -s)
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    sudo chmod 644 /usr/share/keyrings/cloud.google.gpg
    sudo apt-get update
    sudo apt-get install -y gcsfuse rsync git

    # Set up RAM disk
    sudo mkdir -p $RAM_DISK_PATH
    sudo mount -t tmpfs -o size=$RAM_DISK_SIZE tmpfs $RAM_DISK_PATH
    sudo chown $(logname):$(logname) $RAM_DISK_PATH

    # Mount GCS bucket temporarily to copy models
    mkdir -p $GCS_MOUNT_DIR
    gcsfuse $GCS_BUCKET_NAME $GCS_MOUNT_DIR

    # Create models directory in RAM disk and copy models from GCS
    mkdir -p $MODELS_PATH/{checkpoints,loras,vae,controlnet,clip,unet,diffusion_models}
    echo "Copying models from GCS to RAM disk..."
    if [ "$(ls -A $GCS_MOUNT_DIR 2>/dev/null)" ]; then
      rsync -ah --progress "$GCS_MOUNT_DIR/" "$MODELS_PATH/"
      echo "✅ Models copied to RAM disk!"
    else
      echo "No models found in GCS bucket, continuing with empty models directory"
    fi

    # Clean install of ComfyUI directly to RAM disk
    echo "Installing ComfyUI to RAM disk..."
    cd $RAM_DISK_PATH
    git clone https://github.com/comfyanonymous/ComfyUI.git
    cd ComfyUI
    
    # Install Python dependencies
    pip install --upgrade pip
    pip install -r requirements.txt

    # Install ComfyUI Manager
    cd custom_nodes
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    cd ..
    pip install -r custom_nodes/ComfyUI-Manager/requirements.txt

    # Configure ComfyUI to use RAM disk models
    cat > extra_model_paths.yaml << CONFIG_EOF
ramdisk_models:
  base_path: $MODELS_PATH
  checkpoints: checkpoints
  loras: loras
  vae: vae
  controlnet: controlnet
  clip: clip
  unet: unet
  diffusion_models: diffusion_models
CONFIG_EOF

    # Unmount GCS (we've copied everything we need)
    fusermount -u $GCS_MOUNT_DIR || true
    rmdir $GCS_MOUNT_DIR

    echo "✅ ComfyUI installation complete on RAM disk!"
    echo "Starting ComfyUI server..."

    # Start ComfyUI as the user (not as root)
    sudo -u $(logname) -H bash -c "cd $COMFY_PATH && python main.py --listen --port ${var.comfyui_port}"
  EOF

  tags = local.instance_tags

  labels = local.common_labels
}


# --- (Firewall, IAM, and Alerting sections remain the same) ---

# --------------------------------------------------------------------
# 5. Firewall & IAM for IAP
# --------------------------------------------------------------------
resource "google_compute_firewall" "allow_ssh_via_iap" {
  name          = var.firewall_name
  network       = google_compute_network.comfy_net.self_link
  source_ranges = var.iap_source_ranges

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = local.instance_tags
}

resource "google_compute_firewall" "allow_all_from_specific_ip" {
  name          = "${var.firewall_name}-specific-ip"
  network       = google_compute_network.comfy_net.self_link
  source_ranges = ["${var.allowed_ip_address}/32"]

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  target_tags = local.instance_tags
}

resource "google_project_iam_member" "iap_tunnel_user" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${var.iap_user_email}"
}


# --------------------------------------------------------------------
# 6. Proactive Alerting for Integrity Failure
# --------------------------------------------------------------------
resource "google_monitoring_notification_channel" "email" {
  display_name = "Email Alert Channel"
  type         = "email"
  labels = {
    email_address = var.notification_email
  }
}

resource "google_logging_metric" "integrity_failures" {
  name   = "shielded-vm-integrity-failure-metric"
  filter = "resource.type=\"gce_instance\" AND logName:\"logs/compute.googleapis.com%2Fshielded_vm_integrity\" AND jsonPayload.lateBootReportEvent.policyEvaluationPassed=\"false\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "integrity_alert_policy" {
  display_name = "Shielded VM Integrity Failure"
  combiner     = "OR"
  conditions {
    display_name = "Triggers if there is at least one integrity failure in 5 minutes"
    condition_threshold {
      filter     = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.integrity_failures.name}\" AND resource.type=\"gce_instance\""
      duration   = "300s"
      comparison = "COMPARISON_GT"
      trigger {
        count = 1
      }
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }
  notification_channels = [
    google_monitoring_notification_channel.email.id
  ]
}
