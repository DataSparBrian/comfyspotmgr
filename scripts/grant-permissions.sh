#!/bin/bash

# grant-permissions.sh
# ComfySpotMgr - Script to grant necessary permissions for ComfyUI Spot deployment
# Usage: ./grant-permissions.sh USER_EMAIL [PROJECT_ID]

set -e

# Check if user email is provided
if [ -z "$1" ]; then
    echo "Usage: $0 USER_EMAIL [PROJECT_ID]"
    echo "Example: $0 user@example.com my-gcp-project"
    echo ""
    echo "If PROJECT_ID is not provided, the current gcloud project will be used."
    exit 1
fi

USER_EMAIL="$1"
PROJECT_ID="${2:-$(gcloud config get-value project 2>/dev/null)}"

# Validate PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo "Error: No project ID specified and no default project configured."
    echo "Please provide PROJECT_ID as second parameter or set default project:"
    echo "  gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "======================================================"
echo "ComfySpotMgr - Granting deployment permissions"
echo "======================================================"
echo "User Email: $USER_EMAIL"
echo "Project ID: $PROJECT_ID"
echo ""

# Confirm before proceeding
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Granting permissions..."

# Enable required APIs first
echo "Enabling required Google Cloud APIs..."
REQUIRED_APIS=(
    "compute.googleapis.com"
    "storage.googleapis.com" 
    "iam.googleapis.com"
    "monitoring.googleapis.com"
    "logging.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    echo "Enabling $api..."
    if gcloud services enable "$api" --project="$PROJECT_ID" 2>/dev/null; then
        echo "  ✅ $api enabled"
    else
        echo "  ⚠️  $api may already be enabled or you may lack permissions"
    fi
done

echo ""
echo "Waiting 10 seconds for APIs to propagate..."
sleep 10

echo ""
echo "Granting user permissions..."

# Define the required roles
ROLES=(
    "roles/compute.instanceAdmin.v1"
    "roles/compute.networkAdmin"
    "roles/compute.securityAdmin"
    "roles/iam.serviceAccountAdmin"
    "roles/storage.admin"
    "roles/monitoring.editor"
    "roles/logging.configWriter"
    "roles/serviceusage.serviceUsageAdmin"
)

# Grant each role
for role in "${ROLES[@]}"; do
    echo "Granting $role..."
    if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="user:$USER_EMAIL" \
        --role="$role" \
        --quiet > /dev/null 2>&1; then
        echo "  ✅ Successfully granted $role"
    else
        echo "  ❌ Failed to grant $role"
        echo "     This might be because the user already has this role or you don't have permission to grant it."
    fi
done

echo ""
echo "======================================================"
echo "Permission Grant Complete"
echo "======================================================"
echo ""
echo "The user $USER_EMAIL should now have the necessary permissions to:"
echo "  • Deploy ComfySpotMgr instances"
echo "  • Create VPC networks and subnets"
echo "  • Manage firewall rules"
echo "  • Create service accounts"
echo "  • Create and manage GCS buckets"
echo "  • Set up monitoring and logging"
echo ""
echo "Next steps for the user:"
echo "1. Switch to your regular user account: gcloud auth login your-user@domain.com"
echo "2. Clone this repository (if not already done)"
echo "3. Run the ComfySpotMgr setup: make setup"
echo "4. Deploy your instance: make apply"
echo ""
echo "For troubleshooting, the user can verify their permissions with:"
echo "  gcloud projects get-iam-policy $PROJECT_ID --flatten=\"bindings[].members\" --format=\"table(bindings.role)\" --filter=\"bindings.members:$USER_EMAIL\""