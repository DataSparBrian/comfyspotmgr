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
