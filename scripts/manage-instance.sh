#!/bin/bash

# manage-instance.sh
# ComfySpotMgr - Helper script for managing ComfyUI spot instance lifecycle
# Usage: ./scripts/manage-instance.sh [start|stop|status|ssh|forward|logs]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TFVARS_FILE="$PROJECT_ROOT/terraform.tfvars"

# Check if terraform.tfvars exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo "❌ terraform.tfvars not found!"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and fill in your values."
    exit 1
fi

# Extract values from terraform.tfvars
get_tfvar() {
    grep "^$1" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo ""
}

PROJECT_ID=$(get_tfvar "project_id")
INSTANCE_NAME="comfy-spot"  # Default from variables.tf
ZONE="us-central1-a"        # Default from variables.tf
COMFYUI_PORT="8188"         # Default from variables.tf

# Override with custom values if they exist
CUSTOM_INSTANCE=$(get_tfvar "instance_name")
CUSTOM_ZONE=$(get_tfvar "zone")
CUSTOM_PORT=$(get_tfvar "comfyui_port")

[ -n "$CUSTOM_INSTANCE" ] && INSTANCE_NAME="$CUSTOM_INSTANCE"
[ -n "$CUSTOM_ZONE" ] && ZONE="$CUSTOM_ZONE"
[ -n "$CUSTOM_PORT" ] && COMFYUI_PORT="$CUSTOM_PORT"

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Could not find project_id in terraform.tfvars"
    exit 1
fi

# Function to check instance status
check_instance_status() {
    gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND"
}

# Function to wait for instance to be ready
wait_for_ready() {
    echo "Waiting for instance to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(check_instance_status)
        if [ "$status" = "RUNNING" ]; then
            echo "✅ Instance is running"
            return 0
        fi
        echo "Instance status: $status (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    echo "❌ Instance failed to start within expected time"
    return 1
}

case "${1:-status}" in
    "start")
        echo "Starting ComfyUI instance..."
        status=$(check_instance_status)
        
        if [ "$status" = "RUNNING" ]; then
            echo "✅ Instance is already running"
        elif [ "$status" = "NOT_FOUND" ]; then
            echo "Instance not found. Creating with Terraform..."
            cd "$PROJECT_ROOT"
            terraform apply -var-file="terraform.tfvars" -auto-approve
        else
            gcloud compute instances start "$INSTANCE_NAME" \
                --zone="$ZONE" \
                --project="$PROJECT_ID"
            wait_for_ready
        fi
        
        echo ""
        echo "🎉 ComfyUI instance is ready!"
        echo "External IP: $(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(networkInterfaces[0].accessConfigs[0].natIP)")"
        echo ""
        echo "Next steps:"
        echo "  SSH:          ./scripts/manage-instance.sh ssh"
        echo "  Port forward: ./scripts/manage-instance.sh forward"
        echo "  View logs:    ./scripts/manage-instance.sh logs"
        ;;
        
    "stop")
        echo "Stopping ComfyUI instance..."
        status=$(check_instance_status)
        
        if [ "$status" = "RUNNING" ]; then
            gcloud compute instances stop "$INSTANCE_NAME" \
                --zone="$ZONE" \
                --project="$PROJECT_ID"
            echo "✅ Instance stopped"
        elif [ "$status" = "NOT_FOUND" ]; then
            echo "❌ Instance not found"
        else
            echo "✅ Instance is already stopped (status: $status)"
        fi
        ;;
        
    "status")
        status=$(check_instance_status)
        echo "Instance Status: $status"
        
        if [ "$status" = "RUNNING" ]; then
            external_ip=$(gcloud compute instances describe "$INSTANCE_NAME" \
                --zone="$ZONE" \
                --project="$PROJECT_ID" \
                --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
            echo "External IP: $external_ip"
            echo "ComfyUI URL: http://$external_ip:$COMFYUI_PORT"
        fi
        ;;
        
    "ssh")
        echo "Connecting via SSH..."
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --project="$PROJECT_ID" \
            --tunnel-through-iap
        ;;
        
    "forward")
        echo "Setting up port forwarding..."
        echo "ComfyUI will be available at: http://localhost:$COMFYUI_PORT"
        echo "Press Ctrl+C to stop port forwarding"
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --project="$PROJECT_ID" \
            --tunnel-through-iap \
            -- -L "$COMFYUI_PORT:localhost:$COMFYUI_PORT"
        ;;
        
    "logs")
        echo "Viewing startup logs..."
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --project="$PROJECT_ID" \
            --tunnel-through-iap \
            --command="sudo journalctl -u google-startup-scripts -f"
        ;;
        
    "destroy")
        echo "⚠️  WARNING: This will destroy the instance and all data in RAM disk!"
        read -p "Are you sure? Type 'yes' to confirm: " -r
        if [ "$REPLY" = "yes" ]; then
            cd "$PROJECT_ROOT"
            terraform destroy -target=google_compute_instance.comfy_spot_vm -var-file="terraform.tfvars"
        else
            echo "Cancelled"
        fi
        ;;
        
    *)
        echo "Usage: $0 [start|stop|status|ssh|forward|logs|destroy]"
        echo ""
        echo "Commands:"
        echo "  start    - Start or create the ComfyUI instance"
        echo "  stop     - Stop the instance (preserves disk)"
        echo "  status   - Show current instance status"
        echo "  ssh      - SSH into the instance"
        echo "  forward  - Forward ComfyUI port to YOUR PC's localhost (port $COMFYUI_PORT)"
        echo "  logs     - View startup script logs"
        echo "  destroy  - Destroy the instance (saves costs)"
        echo ""
        echo "Cost-saving workflow:"
        echo "  1. ./scripts/manage-instance.sh start"
        echo "  2. ./scripts/manage-instance.sh forward"
        echo "  3. Use ComfyUI at http://localhost:8188"
        echo "  4. ./scripts/manage-instance.sh destroy (when done)"
        exit 1
        ;;
esac