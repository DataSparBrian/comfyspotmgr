#!/bin/bash

# upload-models.sh
# ComfySpotMgr - Helper script for uploading models to GCS bucket
# Usage: ./scripts/upload-models.sh [model-file-or-directory]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TFVARS_FILE="$PROJECT_ROOT/terraform.tfvars"

# Check if terraform.tfvars exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo "❌ terraform.tfvars not found!"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and fill in your values."
    exit 1
fi

# Extract bucket name from terraform.tfvars
get_tfvar() {
    grep "^$1" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo ""
}

PROJECT_ID=$(get_tfvar "project_id")
BUCKET_NAME=$(get_tfvar "bucket_name")

# Use default if not specified
if [ -z "$BUCKET_NAME" ]; then
    BUCKET_NAME="comfy-spot-model-storage"
fi

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Could not find project_id in terraform.tfvars"
    exit 1
fi

BUCKET_URL="gs://$BUCKET_NAME"

# Check if bucket exists
if ! gsutil ls "$BUCKET_URL" >/dev/null 2>&1; then
    echo "❌ Bucket $BUCKET_URL not found or not accessible"
    echo "Make sure you've deployed the infrastructure with 'terraform apply'"
    exit 1
fi

# Function to detect model type based on filename
detect_model_type() {
    local filename=$(basename "$1")
    local extension="${filename##*.}"
    
    case "$filename" in
        *"lora"*|*"LoRA"*) echo "loras" ;;
        *"vae"*|*"VAE"*) echo "vae" ;;
        *"controlnet"*|*"ControlNet"*) echo "controlnet" ;;
        *"clip"*|*"CLIP"*) echo "clip" ;;
        *"unet"*|*"UNet"*) echo "unet" ;;
        *.safetensors|*.ckpt|*.pt|*.pth) echo "checkpoints" ;;
        *) echo "checkpoints" ;;  # Default to checkpoints
    esac
}

# Function to upload a single file
upload_file() {
    local source_file="$1"
    local model_type=$(detect_model_type "$source_file")
    local filename=$(basename "$source_file")
    local dest="$BUCKET_URL/$model_type/$filename"
    
    echo "📤 Uploading $filename to $model_type/"
    if gsutil cp "$source_file" "$dest"; then
        echo "✅ Uploaded: $dest"
    else
        echo "❌ Failed to upload: $source_file"
        return 1
    fi
}

# Function to upload directory
upload_directory() {
    local source_dir="$1"
    
    echo "📂 Uploading directory: $source_dir"
    
    # Upload preserving directory structure
    if gsutil -m cp -r "$source_dir"/* "$BUCKET_URL/"; then
        echo "✅ Directory uploaded successfully"
    else
        echo "❌ Failed to upload directory: $source_dir"
        return 1
    fi
}

# Main logic
if [ $# -eq 0 ]; then
    echo "Usage: $0 [model-file-or-directory]"
    echo ""
    echo "Examples:"
    echo "  $0 model.safetensors                    # Upload single model"
    echo "  $0 ~/models/                           # Upload entire directory"
    echo "  $0 lora_model.safetensors              # Auto-detected as LoRA"
    echo ""
    echo "Model types are auto-detected based on filename:"
    echo "  - Files with 'lora' → loras/"
    echo "  - Files with 'vae' → vae/"
    echo "  - Files with 'controlnet' → controlnet/"
    echo "  - Other .safetensors/.ckpt → checkpoints/"
    echo ""
    echo "Current bucket: $BUCKET_URL"
    echo "Bucket contents:"
    gsutil ls -l "$BUCKET_URL" 2>/dev/null | head -20 || echo "  (empty or inaccessible)"
    exit 1
fi

SOURCE="$1"

if [ ! -e "$SOURCE" ]; then
    echo "❌ File or directory not found: $SOURCE"
    exit 1
fi

echo "======================================================"
echo "Uploading Models to ComfyUI Storage"
echo "======================================================"
echo "Source: $SOURCE"
echo "Bucket: $BUCKET_URL"
echo ""

if [ -d "$SOURCE" ]; then
    upload_directory "$SOURCE"
elif [ -f "$SOURCE" ]; then
    upload_file "$SOURCE"
else
    echo "❌ Invalid source: $SOURCE"
    exit 1
fi

echo ""
echo "✅ Upload complete!"
echo ""
echo "To use the new models:"
echo "1. Restart your ComfyUI instance: ./scripts/manage-instance.sh stop && ./scripts/manage-instance.sh start"
echo "2. The models will be copied to RAM disk during startup"
echo ""
echo "Current bucket contents:"
gsutil ls -lh "$BUCKET_URL/**" 2>/dev/null | head -20 || echo "Unable to list contents"