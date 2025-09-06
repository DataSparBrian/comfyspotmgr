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

  # UPDATED - Startup script with Google Chat notifications
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    
    # Function to get or create the ComfyUI user
    get_comfy_user() {
        # Try to find a non-root user (typically the one who created the instance)
        local user=$(getent passwd | grep -E ':/home/[^:]+:' | grep -v nobody | head -1 | cut -d: -f1)
        if [ -z "$user" ]; then
            # If no user found, create a dedicated comfyui user
            user="comfyui"
            if ! id "$user" &>/dev/null; then
                useradd -m -s /bin/bash "$user"
                usermod -aG sudo "$user"
                echo "Created user: $user"
            fi
        fi
        echo "$user"
    }
    
    # Variables
    COMFY_USER=$(get_comfy_user)
    USER_HOME=$(eval echo ~$COMFY_USER)
    echo "Using ComfyUI user: $COMFY_USER"
    echo "User home directory: $USER_HOME"
    GCS_BUCKET_NAME="${google_storage_bucket.model_storage_bucket.name}"
    GCS_MOUNT_DIR="$USER_HOME/gcs_models"
    RAM_DISK_SIZE="${var.ram_disk_size}"
    RAM_DISK_PATH="/mnt/ramdisk"
    COMFY_PATH="$RAM_DISK_PATH/ComfyUI"
    MODELS_PATH="$RAM_DISK_PATH/models"
    WEBHOOK_URL="${var.google_chat_webhook_url}"
    INSTANCE_NAME="${var.instance_name}"
    INSTANCE_ZONE="${var.zone}"
    COMFY_PORT="${var.comfyui_port}"

    # Function to send Google Chat notification
    send_chat_notification() {
        local message="$1"
        echo "[ComfySpotMgr] Sending Chat Notification: $message"
        curl -s -X POST -H 'Content-Type: application/json' "$WEBHOOK_URL" \
            -d "{\"text\": \"$message\"}" > /dev/null || true
        sleep 1
    }

    # Get public IP (will be available after instance starts)
    get_public_ip() {
        curl -s -H "Metadata-Flavor: Google" \
            http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip || echo "localhost"
    }

    # Send startup notification
    send_chat_notification "🚀 ComfyUI deployment starting on $INSTANCE_NAME in $INSTANCE_ZONE..."

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
    sudo chown $COMFY_USER:$COMFY_USER $RAM_DISK_PATH

    # Mount GCS bucket temporarily to copy models
    mkdir -p $GCS_MOUNT_DIR
    gcsfuse $GCS_BUCKET_NAME $GCS_MOUNT_DIR

    # Create models directory in RAM disk and copy models from GCS
    mkdir -p $MODELS_PATH/{checkpoints,loras,vae,controlnet,clip,unet,diffusion_models}
    echo "Copying models from GCS to RAM disk..."
    if [ "$(ls -A $GCS_MOUNT_DIR 2>/dev/null)" ]; then
      rsync -ah --progress "$GCS_MOUNT_DIR/" "$MODELS_PATH/"
      echo "✅ Models copied to RAM disk!"
      send_chat_notification "📦 Models copied to $RAM_DISK_SIZE RAM disk on $INSTANCE_NAME"
    else
      echo "No models found in GCS bucket, continuing with empty models directory"
      send_chat_notification "📦 No models found in GCS bucket - continuing with empty models directory"
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
    send_chat_notification "✅ ComfyUI installation complete on $INSTANCE_NAME - starting server..."

    # Get the public IP before starting the server
    PUBLIC_IP=$(get_public_ip)
    
    # Create a background process to send ready notification once ComfyUI is responsive
    (
        sleep 30  # Give ComfyUI time to start
        for i in {1..20}; do
            if curl -s --connect-timeout 3 "http://localhost:$COMFY_PORT/" > /dev/null 2>&1; then
                send_chat_notification "🎉 ComfyUI Server Ready!
📍 Instance: $INSTANCE_NAME ($INSTANCE_ZONE)
🌐 Access: http://$PUBLIC_IP:$COMFY_PORT
⚡ Running on $RAM_DISK_SIZE RAM disk
🎯 Click the link above to launch ComfyUI on your iPad!"
                break
            fi
            sleep 10
        done
    ) &

    echo "Starting ComfyUI server on port $COMFY_PORT..."
    # Start ComfyUI as the user (not as root)
    sudo -u $COMFY_USER -H bash -c "cd $COMFY_PATH && python3 main.py --listen --port $COMFY_PORT"
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
# 6. ComfyUI Service Monitoring & Google Chat Notifications
# --------------------------------------------------------------------

# Google Chat webhook notification channel
resource "google_monitoring_notification_channel" "google_chat_webhook" {
  display_name = "ComfyUI Ready - Google Chat"
  type         = "webhook_tokenauth"
  labels = {
    url = var.google_chat_webhook_url
  }
  user_labels = {
    purpose = "comfyui-ready-notifications"
  }
}

# HTTP uptime check to monitor ComfyUI service
resource "google_monitoring_uptime_check_config" "comfyui_uptime_check" {
  display_name = "ComfyUI Service Check"
  timeout      = "10s"
  period       = "300s" # Check every 5 minutes

  http_check {
    port           = var.comfyui_port
    use_ssl        = false
    path           = "/"
    request_method = "GET"
  }

  monitored_resource {
    type = "gce_instance"
    labels = {
      project_id  = var.project_id
      instance_id = google_compute_instance.comfy_spot_vm.instance_id
      zone        = var.zone
    }
  }

  depends_on = [google_compute_instance.comfy_spot_vm]
}

# Alert policy for ComfyUI service availability
resource "google_monitoring_alert_policy" "comfyui_ready_alert" {
  display_name = "ComfyUI Service Ready"
  combiner     = "OR"
  
  conditions {
    display_name = "ComfyUI HTTP check succeeds"
    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.comfyui_uptime_check.uptime_check_id}\""
      duration       = "60s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
      }
      
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.google_chat_webhook.id
  ]

  alert_strategy {
    auto_close = "1800s" # Auto-close after 30 minutes
  }
}
