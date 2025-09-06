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
# 4. Hyperdisk Balanced for Persistent Caching (Conditional)
# --------------------------------------------------------------------
resource "google_compute_disk" "comfy_persistent_cache" {
  count = var.enable_persistent_cache ? 1 : 0
  
  name = "${var.instance_name}-persistent-cache"
  type = var.persistent_disk_type
  zone = var.zone
  size = var.persistent_disk_size

  labels = merge(local.common_labels, {
    purpose = "comfyui-cache"
    cache_type = "persistent"
  })

  # Hyperdisk performance optimization
  provisioned_iops       = var.persistent_disk_type == "hyperdisk-balanced" ? 3000 : null
  provisioned_throughput = var.persistent_disk_type == "hyperdisk-balanced" ? 140 : null
}

# --------------------------------------------------------------------
# 5. The Spot VM Instance (Updated for Hyperdisk Caching)
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
    instance_termination_action = "STOP"
    on_host_maintenance         = "TERMINATE"
    
    # Local SSD recovery timeout - discard data immediately on termination
    local_ssd_recovery_timeout {
      seconds = 0
    }
    
    # Conditional max run duration block
    dynamic "max_run_duration" {
      for_each = var.enable_max_runtime ? [1] : []
      content {
        seconds = var.max_runtime_hours * 3600
      }
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.comfy_subnet.id
    access_config {
      # Ephemeral public IP
    }
  }

  # Conditionally attach the persistent cache disk
  dynamic "attached_disk" {
    for_each = var.enable_persistent_cache ? [1] : []
    content {
      source      = google_compute_disk.comfy_persistent_cache[0].id
      device_name = "persistent-cache"
      mode        = "READ_WRITE"
    }
  }

  # UPDATED - Multi-tier caching startup script with 5-minute sync intervals
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    
    # Function to get or create the ComfyUI user
    get_comfy_user() {
        local user=$(getent passwd | grep -E ':/home/[^:]+:' | grep -v nobody | head -1 | cut -d: -f1)
        if [ -z "$user" ]; then
            user="comfyui"
            if ! id "$user" &>/dev/null; then
                useradd -m -s /bin/bash "$user"
                usermod -aG sudo "$user"
                echo "Created user: $user"
            fi
        fi
        echo "$user"
    }
    
    # Variables - Enhanced for multi-tier caching
    COMFY_USER=$(get_comfy_user)
    USER_HOME=$(eval echo ~$COMFY_USER)
    echo "Using ComfyUI user: $COMFY_USER"
    echo "User home directory: $USER_HOME"
    
    # Storage paths
    GCS_BUCKET_NAME="${google_storage_bucket.model_storage_bucket.name}"
    GCS_MOUNT_DIR="$USER_HOME/gcs_models"
    RAM_DISK_SIZE="${var.ram_disk_size}"
    RAM_DISK_PATH="/mnt/ramdisk"
    COMFY_PATH="$RAM_DISK_PATH/ComfyUI"
    MODELS_PATH="$RAM_DISK_PATH/models"
    LOCAL_SSD_CACHE="/opt/comfyui_cache"
    PERSISTENT_DISK_PATH="/mnt/persistent"
    PERSISTENT_CACHE="$PERSISTENT_DISK_PATH/comfyui_cache"
    
    # Configuration
    WEBHOOK_URL="${var.google_chat_webhook_url}"
    INSTANCE_NAME="${var.instance_name}"
    INSTANCE_ZONE="${var.zone}"
    COMFY_PORT="${var.comfyui_port}"
    MAX_RUNTIME_HOURS="${var.max_runtime_hours}"
    SHUTDOWN_WARNING_MINUTES="${var.shutdown_warning_minutes}"
    ENABLE_MAX_RUNTIME="${var.enable_max_runtime}"
    CACHE_SYNC_INTERVAL="${var.cache_sync_interval}"
    ENABLE_PERSISTENT_CACHE="${var.enable_persistent_cache}"

    # Function to send Google Chat notification
    send_chat_notification() {
        local message="$1"
        echo "[ComfySpotMgr] Sending Chat Notification: $message"
        curl -s -X POST -H 'Content-Type: application/json' "$WEBHOOK_URL" \
            -d "{\"text\": \"$message\"}" > /dev/null || true
        sleep 1
    }

    # Function to validate cache integrity
    validate_cache() {
        local cache_path="$1"
        local cache_name="$2"
        
        if [ ! -d "$cache_path/ComfyUI" ]; then
            echo "❌ $cache_name: ComfyUI directory missing"
            return 1
        fi
        
        if [ ! -f "$cache_path/ComfyUI/main.py" ]; then
            echo "❌ $cache_name: main.py missing"
            return 1
        fi
        
        if [ ! -d "$cache_path/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
            echo "❌ $cache_name: ComfyUI-Manager missing"
            return 1
        fi
        
        if [ ! -f "$cache_path/.cache_timestamp" ]; then
            echo "⚠️  $cache_name: No timestamp found"
            return 1
        fi
        
        echo "✅ $cache_name: Cache validation passed"
        return 0
    }

    # Function to copy from cache to RAM disk
    copy_from_cache() {
        local cache_path="$1"
        local cache_name="$2"
        
        echo "📋 Copying from $cache_name to RAM disk..."
        send_chat_notification "⚡ Found $cache_name! Fast recovery in progress on $INSTANCE_NAME..."
        
        # Copy ComfyUI installation
        cp -R "$cache_path/ComfyUI" "$RAM_DISK_PATH/"
        
        # Copy models if they exist
        if [ -d "$cache_path/models" ]; then
            cp -R "$cache_path/models" "$RAM_DISK_PATH/"
        fi
        
        chown -R $COMFY_USER:$COMFY_USER "$RAM_DISK_PATH"
        
        echo "✅ $cache_name recovery completed!"
        send_chat_notification "🚀 $cache_name recovery completed in ~30 seconds on $INSTANCE_NAME!"
        return 0
    }

    # Function to create cache timestamp
    create_cache_timestamp() {
        local cache_path="$1"
        echo "$(date -u +%Y%m%d_%H%M%S)" > "$cache_path/.cache_timestamp"
        echo "Cache created: $(date)" >> "$cache_path/.cache_info"
        echo "Instance: $INSTANCE_NAME" >> "$cache_path/.cache_info"
    }

    # Function to setup persistent disk
    setup_persistent_disk() {
        if [ "$ENABLE_PERSISTENT_CACHE" = "true" ]; then
            echo "🔧 Setting up persistent disk..."
            
            # Find the persistent disk device
            PERSISTENT_DEVICE=$(lsblk -no NAME,SERIAL | grep persistent-cache | awk '{print "/dev/" $1}' | head -1)
            
            if [ -n "$PERSISTENT_DEVICE" ]; then
                echo "Found persistent disk: $PERSISTENT_DEVICE"
                
                # Create mount point
                mkdir -p "$PERSISTENT_DISK_PATH"
                
                # Check if filesystem exists, if not create it
                if ! blkid "$PERSISTENT_DEVICE" > /dev/null 2>&1; then
                    echo "Creating filesystem on persistent disk..."
                    mkfs.ext4 -F "$PERSISTENT_DEVICE"
                fi
                
                # Mount the persistent disk
                mount "$PERSISTENT_DEVICE" "$PERSISTENT_DISK_PATH"
                echo "$PERSISTENT_DEVICE $PERSISTENT_DISK_PATH ext4 defaults 0 2" >> /etc/fstab
                
                # Set ownership
                chown $COMFY_USER:$COMFY_USER "$PERSISTENT_DISK_PATH"
                
                echo "✅ Persistent disk mounted at $PERSISTENT_DISK_PATH"
            else
                echo "⚠️  Persistent disk not found, disabling persistent cache"
                ENABLE_PERSISTENT_CACHE="false"
            fi
        fi
    }

    # Function for fresh ComfyUI installation
    fresh_install() {
        echo "🔄 Performing fresh ComfyUI installation..."
        send_chat_notification "🔄 No cache found - performing fresh install on $INSTANCE_NAME (this may take 5-10 minutes)..."
        
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
            echo "No models found in GCS bucket"
        fi
        
        # Install ComfyUI
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
        cat > extra_model_paths.yaml << 'CONFIG_EOF'
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
        
        # Set ownership
        chown -R $COMFY_USER:$COMFY_USER $RAM_DISK_PATH
        
        # Unmount GCS
        fusermount -u $GCS_MOUNT_DIR || true
        rmdir $GCS_MOUNT_DIR
        
        echo "✅ Fresh installation completed!"
        send_chat_notification "✅ Fresh ComfyUI installation completed on $INSTANCE_NAME"
    }

    # Function to create shutdown service
    create_shutdown_service() {
        cat > /etc/systemd/system/comfy-cache-sync.service << 'SERVICE_EOF'
[Unit]
Description=ComfyUI Cache Sync on Shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/bin/true
ExecStop=/opt/comfyui-shutdown-sync.sh
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
SERVICE_EOF

        # Create shutdown sync script
        cat > /opt/comfyui-shutdown-sync.sh << 'SHUTDOWN_EOF'
#!/bin/bash
echo "🛑 Shutdown detected - syncing caches..."

RAM_DISK_PATH="/mnt/ramdisk"
LOCAL_SSD_CACHE="/opt/comfyui_cache"
PERSISTENT_CACHE="/mnt/persistent/comfyui_cache"
WEBHOOK_URL="${var.google_chat_webhook_url}"
INSTANCE_NAME="${var.instance_name}"

send_notification() {
    curl -s -X POST -H 'Content-Type: application/json' "$WEBHOOK_URL" \
        -d "{\"text\": \"$1\"}" > /dev/null 2>&1 || true
}

if [ -d "$RAM_DISK_PATH/ComfyUI" ]; then
    send_notification "💾 Syncing caches before shutdown on $INSTANCE_NAME..."
    
    # Sync to Local SSD cache
    mkdir -p "$LOCAL_SSD_CACHE"
    rsync -a --delete "$RAM_DISK_PATH/" "$LOCAL_SSD_CACHE/" 2>/dev/null || true
    echo "$(date -u +%Y%m%d_%H%M%S)" > "$LOCAL_SSD_CACHE/.cache_timestamp"
    
    # Sync to persistent cache if available
    if [ -d "/mnt/persistent" ] && mountpoint -q "/mnt/persistent"; then
        mkdir -p "$PERSISTENT_CACHE"
        rsync -a --delete "$RAM_DISK_PATH/" "$PERSISTENT_CACHE/" 2>/dev/null || true
        echo "$(date -u +%Y%m%d_%H%M%S)" > "$PERSISTENT_CACHE/.cache_timestamp"
    fi
    
    send_notification "✅ Cache sync completed on $INSTANCE_NAME - shutdown proceeding"
fi
SHUTDOWN_EOF

        chmod +x /opt/comfyui-shutdown-sync.sh
        systemctl enable comfy-cache-sync.service
        systemctl start comfy-cache-sync.service
    }

    # Function to start background sync processes
    start_background_sync() {
        cat > /opt/comfyui-background-sync.sh << 'SYNC_EOF'
#!/bin/bash
RAM_DISK_PATH="/mnt/ramdisk"
LOCAL_SSD_CACHE="/opt/comfyui_cache"
PERSISTENT_CACHE="/mnt/persistent/comfyui_cache"
SYNC_INTERVAL="$1"

while true; do
    if [ -d "$RAM_DISK_PATH/ComfyUI" ]; then
        # Sync to Local SSD
        mkdir -p "$LOCAL_SSD_CACHE"
        rsync -a --delete "$RAM_DISK_PATH/" "$LOCAL_SSD_CACHE/" 2>/dev/null || true
        echo "$(date -u +%Y%m%d_%H%M%S)" > "$LOCAL_SSD_CACHE/.cache_timestamp"
        
        # Sync to persistent cache if available
        if [ -d "/mnt/persistent" ] && mountpoint -q "/mnt/persistent"; then
            mkdir -p "$PERSISTENT_CACHE"
            rsync -a --delete "$RAM_DISK_PATH/" "$PERSISTENT_CACHE/" 2>/dev/null || true
            echo "$(date -u +%Y%m%d_%H%M%S)" > "$PERSISTENT_CACHE/.cache_timestamp"
        fi
    fi
    
    sleep "$SYNC_INTERVAL"
done
SYNC_EOF

        chmod +x /opt/comfyui-background-sync.sh
        nohup /opt/comfyui-background-sync.sh "$CACHE_SYNC_INTERVAL" > /var/log/comfy-sync.log 2>&1 &
        echo "✅ Background sync started with $CACHE_SYNC_INTERVAL second intervals"
    }

    # Function to schedule shutdown warning notification
    schedule_shutdown_warning() {
        if [ "$ENABLE_MAX_RUNTIME" = "true" ]; then
            local warning_seconds=$((MAX_RUNTIME_HOURS * 3600 - SHUTDOWN_WARNING_MINUTES * 60))
            echo "Scheduling shutdown warning notification in $warning_seconds seconds"
            
            cat > /tmp/shutdown_warning.sh << 'WARNING_SCRIPT_EOF'
#!/bin/bash
WEBHOOK_URL="$1"
INSTANCE_NAME="$2"
SHUTDOWN_WARNING_MINUTES="$3"
MAX_RUNTIME_HOURS="$4"

curl -s -X POST -H 'Content-Type: application/json' "$WEBHOOK_URL" \
    -d "{\"text\": \"⚠️ SHUTDOWN WARNING: $INSTANCE_NAME will automatically stop in $SHUTDOWN_WARNING_MINUTES minutes!\n\n🕐 Maximum runtime: $MAX_RUNTIME_HOURS hour(s)\n🛑 Save your work and export any results now\n💾 The instance will be STOPPED (not deleted) to save costs\n🔄 You can restart it anytime from the GCP Console\"}" > /dev/null || true
WARNING_SCRIPT_EOF

            chmod +x /tmp/shutdown_warning.sh
            apt-get install -y at
            systemctl start atd
            systemctl enable atd
            echo "/tmp/shutdown_warning.sh '$WEBHOOK_URL' '$INSTANCE_NAME' '$SHUTDOWN_WARNING_MINUTES' '$MAX_RUNTIME_HOURS'" | at now + $warning_seconds seconds 2>/dev/null || echo "Warning: Could not schedule shutdown notification"
        fi
    }

    # Get public IP
    get_public_ip() {
        curl -s -H "Metadata-Flavor: Google" \
            http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip || echo "localhost"
    }

    # MAIN EXECUTION STARTS HERE
    echo "🚀 Starting ComfyUI with multi-tier caching..."
    send_chat_notification "🚀 ComfyUI deployment starting with multi-tier caching on $INSTANCE_NAME..."

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

    # Setup persistent disk if enabled
    setup_persistent_disk

    # Multi-tier cache detection logic
    CACHE_HIT=false
    
    echo "🔍 Checking cache hierarchy..."
    
    # 1. Check Local SSD cache first (fastest recovery)
    if [ -d "$LOCAL_SSD_CACHE" ] && validate_cache "$LOCAL_SSD_CACHE" "Local SSD Cache"; then
        echo "🎯 Local SSD Cache HIT!"
        copy_from_cache "$LOCAL_SSD_CACHE" "Local SSD Cache"
        CACHE_HIT=true
    # 2. Check Persistent Disk cache second (zone-persistent recovery)  
    elif [ "$ENABLE_PERSISTENT_CACHE" = "true" ] && [ -d "$PERSISTENT_CACHE" ] && validate_cache "$PERSISTENT_CACHE" "Persistent Cache"; then
        echo "🎯 Persistent Cache HIT!"
        copy_from_cache "$PERSISTENT_CACHE" "Persistent Cache"
        # Also copy to Local SSD for next time
        echo "📋 Caching to Local SSD for faster future recovery..."
        mkdir -p "$LOCAL_SSD_CACHE"
        cp -R "$PERSISTENT_CACHE"/* "$LOCAL_SSD_CACHE/"
        create_cache_timestamp "$LOCAL_SSD_CACHE"
        CACHE_HIT=true
    # 3. No cache found - fresh installation required
    else
        echo "❌ No valid cache found - proceeding with fresh installation"
        fresh_install
    fi

    # Create shutdown service and start background sync
    create_shutdown_service
    start_background_sync

    # Schedule shutdown warning if enabled
    schedule_shutdown_warning

    # Get public IP
    PUBLIC_IP=$(get_public_ip)
    
    echo "✅ ComfyUI setup complete - starting server..."
    
    # Background notification once server is ready
    (
        sleep 30
        for i in {1..20}; do
            if curl -s --connect-timeout 3 "http://localhost:$COMFY_PORT/" > /dev/null 2>&1; then
                if [ "$CACHE_HIT" = "true" ]; then
                    send_chat_notification "🎉 ComfyUI Ready via CACHE! ⚡\n📍 Instance: $INSTANCE_NAME ($INSTANCE_ZONE)\n🌐 Access: http://$PUBLIC_IP:$COMFY_PORT\n⚡ Running on $RAM_DISK_SIZE RAM disk with multi-tier caching\n🚀 Recovery took ~30 seconds!"
                else
                    send_chat_notification "🎉 ComfyUI Ready! \n📍 Instance: $INSTANCE_NAME ($INSTANCE_ZONE)\n🌐 Access: http://$PUBLIC_IP:$COMFY_PORT\n⚡ Running on $RAM_DISK_SIZE RAM disk with multi-tier caching\n📦 Fresh installation completed"
                fi
                break
            fi
            sleep 10
        done
    ) &

    echo "Starting ComfyUI server on port $COMFY_PORT..."
    sudo -u $COMFY_USER -H bash -c "cd $COMFY_PATH && python3 main.py --listen --port $COMFY_PORT"
  EOF

  tags = local.instance_tags

  labels = local.common_labels
}


# --- (Firewall, IAM, and Alerting sections remain the same) ---

# --------------------------------------------------------------------
# 6. Firewall & IAM for IAP
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
# 7. ComfyUI Service Monitoring & Google Chat Notifications
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
