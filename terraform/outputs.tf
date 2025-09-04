# ComfySpotMgr - Terraform Outputs
# ComfyUI Spot Deployment Manager outputs

output "instance_name" {
  description = "Name of the created compute instance"
  value       = google_compute_instance.comfy_spot_vm.name
}

output "instance_zone" {
  description = "Zone of the created compute instance"
  value       = google_compute_instance.comfy_spot_vm.zone
}

output "instance_external_ip" {
  description = "External IP address of the compute instance"
  value       = google_compute_instance.comfy_spot_vm.network_interface[0].access_config[0].nat_ip
}

output "storage_bucket_name" {
  description = "Name of the GCS bucket for model storage"
  value       = google_storage_bucket.model_storage_bucket.name
}


output "ssh_command" {
  description = "Command to SSH into the instance via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.comfy_spot_vm.name} --zone=${google_compute_instance.comfy_spot_vm.zone} --tunnel-through-iap"
}

output "port_forward_command" {
  description = "Command to forward ComfyUI port to localhost"
  value       = "gcloud compute ssh ${google_compute_instance.comfy_spot_vm.name} --zone=${google_compute_instance.comfy_spot_vm.zone} --tunnel-through-iap -- -L ${var.comfyui_port}:localhost:${var.comfyui_port}"
}

output "comfyui_url" {
  description = "ComfyUI web interface URL (after port forwarding)"
  value       = "http://localhost:${var.comfyui_port}"
}

# Image selection outputs for validation
output "selected_image_info" {
  description = "Information about the selected Deep Learning VM image"
  value = {
    name         = local.selected_image.name
    family       = local.selected_image.family
    creation_date = local.selected_image.creation_timestamp
    self_link    = local.selected_image.self_link
  }
}

output "image_selection_method" {
  description = "Which candidate image was successfully selected"
  value = local.selected_family
}

output "image_search_criteria" {
  description = "The search criteria used for image selection"
  value = {
    pytorch_pattern = var.pytorch_version_pattern
    cuda_version   = var.cuda_version
    ubuntu_version = var.ubuntu_version
    fallback_family = var.fallback_image_family
  }
}
