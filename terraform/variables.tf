# ComfySpotMgr - Terraform Variables
# ComfyUI Spot Deployment Manager configuration

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  # No default - must be specified in terraform.tfvars
}

variable "region" {
  description = "GCP Region for resources"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "zone" {
  description = "GCP Zone for compute instance"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "subnet_name" {
  description = "Name of the VPC subnet"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "subnet_cidr" {
  description = "CIDR block for the VPC subnet"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "instance_name" {
  description = "Name of the compute instance"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "machine_type" {
  description = "Machine type for the compute instance"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "boot_disk_size" {
  description = "Size of the boot disk in GB"
  type        = number
  # No default - specified in terraform.tfvars
}

# boot_disk_image variable removed - now using data source for latest image

variable "gpu_type" {
  description = "Type of GPU to attach"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "gpu_count" {
  description = "Number of GPUs to attach"
  type        = number
  # No default - specified in terraform.tfvars
}

variable "service_account_id" {
  description = "ID for the service account"
  type        = string
  default     = "comfy-spot-sa"
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Service Account for Comfy Spot VM"
}

variable "bucket_name" {
  description = "Name of the GCS bucket for model storage"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "bucket_location" {
  description = "Location of the GCS bucket"
  type        = string
  # No default - specified in terraform.tfvars
}

variable "bucket_force_destroy" {
  description = "Whether to force destroy the bucket even if not empty"
  type        = bool
  # No default - specified in terraform.tfvars
}

variable "firewall_name" {
  description = "Name of the firewall rule for SSH access"
  type        = string
  default     = "allow-ssh-for-comfy-spot-iap"
}

variable "iap_user_email" {
  description = "Email address of the user who should have IAP tunnel access"
  type        = string
  # No default - must be specified in terraform.tfvars
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  # No default - must be specified in terraform.tfvars
}

variable "enable_shielded_vm" {
  description = "Enable Shielded VM features"
  type        = bool
  default     = true
}

variable "enable_secure_boot" {
  description = "Enable Secure Boot for Shielded VM"
  type        = bool
  default     = true
}

variable "enable_vtpm" {
  description = "Enable vTPM for Shielded VM"
  type        = bool
  default     = true
}

variable "enable_integrity_monitoring" {
  description = "Enable Integrity Monitoring for Shielded VM"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Network tags for the compute instance"
  type        = list(string)
  default     = ["ssh-iap"]
}

variable "allowed_ip_address" {
  description = "Your public IP address for direct access to ComfyUI (get from whatismyip.com)"
  type        = string
  # No default - must be specified in terraform.tfvars for security
}

variable "ram_disk_size" {
  description = "Size of the RAM disk for ultra-fast model access (75G recommended for A3 instances)"
  type        = string
  # No default - must be specified in terraform.tfvars
}

variable "comfyui_port" {
  description = "Port for ComfyUI web interface (8188 is standard)"
  type        = number
  # No default - must be specified in terraform.tfvars
}

variable "iap_source_ranges" {
  description = "Source IP ranges for Identity-Aware Proxy"
  type        = list(string)
  default     = ["35.235.240.0/20"]
}

variable "terraform_state_bucket" {
  description = "Name of the GCS bucket for Terraform state storage (must be globally unique)"
  type        = string
  # No default - must be specified in terraform.tfvars
}

# Image selection is now simplified to use the current supported Deep Learning VM family
# No additional variables needed - using pytorch-2-7-cu128-ubuntu-2204-nvidia-570 directly
