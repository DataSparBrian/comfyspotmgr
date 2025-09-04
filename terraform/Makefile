# ComfySpotMgr - ComfyUI Spot Deployment Manager

.PHONY: help setup plan apply destroy start stop status ssh forward logs upload-models clean

# Default target
help:
	@echo ""
	@echo "=============================================="
	@echo "ComfySpotMgr - ComfyUI Spot Deployment Manager"
	@echo "=============================================="
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  setup         - Interactive setup wizard (run this first!)"
	@echo "  setup-dry-run - Preview setup without making changes"
	@echo ""
	@echo "📦 Deployment:"
	@echo "  plan          - Show Terraform execution plan"
	@echo "  apply         - Deploy infrastructure"
	@echo "  destroy       - Destroy all infrastructure"
	@echo ""
	@echo "Instance Management:"
	@echo "  start         - Start or create the ComfyUI instance"
	@echo "  stop          - Stop the instance (saves costs)"
	@echo "  restart       - Stop and start the instance"
	@echo "  status        - Show instance status"
	@echo "  destroy-vm    - Destroy just the VM (keeps storage)"
	@echo ""
	@echo "Development:"
	@echo "  ssh           - SSH into the instance"
	@echo "  forward       - Forward ComfyUI port to localhost"
	@echo "  logs          - View startup script logs"
	@echo ""
	@echo "Model Management:"
	@echo "  upload-models - Upload models to GCS (usage: make upload-models FILE=model.safetensors)"
	@echo "  list-models   - List models in GCS bucket"
	@echo ""
	@echo "Utilities:"
	@echo "  validate      - Validate Terraform configuration"
	@echo "  clean         - Clean Terraform cache files"

# Check if terraform.tfvars exists
check-config:
	@if [ ! -f terraform.tfvars ]; then \
		echo "❌ terraform.tfvars not found!"; \
		echo "Run 'make setup' to create your configuration."; \
		exit 1; \
	fi

# Interactive setup wizard
setup:
	@$(MAKE) _setup DRY_RUN=false

# Dry-run setup wizard (shows what would be done)
setup-dry-run:
	@$(MAKE) _setup DRY_RUN=true

# Internal setup implementation
_setup:
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "🔍 Starting ComfySpotMgr setup wizard (DRY-RUN MODE)..."; \
		echo "⚠️  This is a dry-run - no changes will be made"; \
	else \
		echo "🚀 Starting ComfySpotMgr setup wizard..."; \
	fi
	@echo ""
	@echo "Step 1: Checking prerequisites..."
	@$(MAKE) _check_prerequisites
	@echo ""
	@echo "Step 2: Configuring deployment..."
	@$(MAKE) _interactive_config
	@echo ""
	@echo "Step 3: Validating billing..."
	@$(MAKE) _check_billing
	@echo ""
	@echo "Step 4: Enabling Google Cloud APIs..."
	@$(MAKE) _enable_apis
	@echo ""
	@echo "Step 5: Setting up Terraform backend..."
	@$(MAKE) _setup_backend
	@echo ""
	@echo "Step 6: Validating Terraform configuration..."
	@$(MAKE) _validate_config
	@echo ""
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "======================================================"; \
		echo "🔍 Dry-Run Complete!"; \
		echo "======================================================"; \
		echo ""; \
		echo "✅ Dry-run completed successfully! No changes were made."; \
		echo ""; \
		echo "To execute for real:"; \
		echo "  make setup     # Run without dry-run"; \
	else \
		echo "======================================================"; \
		echo "🎉 Setup Complete!"; \
		echo "======================================================"; \
		echo ""; \
		echo "✅ Your ComfySpotMgr deployment is ready!"; \
		echo ""; \
		echo "Next steps:"; \
		echo "  1. Review the plan:    make plan"; \
		echo "  2. Deploy:             make apply"; \
		echo "  3. Access ComfyUI:     make forward"; \
	fi
	@echo ""
	@echo "For help: make help"

plan: check-config
	terraform plan -var-file="terraform.tfvars"

apply: check-config
	terraform apply -var-file="terraform.tfvars"

destroy: check-config
	@echo "⚠️  WARNING: This will destroy ALL infrastructure!"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		terraform destroy -var-file="terraform.tfvars"; \
	else \
		echo "Cancelled"; \
	fi

# Instance lifecycle management
start:
	../scripts/manage-instance.sh start

stop:
	../scripts/manage-instance.sh stop

restart: stop
	@sleep 5
	@$(MAKE) start

status:
	../scripts/manage-instance.sh status

destroy-vm:
	../scripts/manage-instance.sh destroy

# Development and debugging
ssh:
	../scripts/manage-instance.sh ssh

forward:
	../scripts/manage-instance.sh forward

logs:
	../scripts/manage-instance.sh logs

# Model management
upload-models:
ifdef FILE
	../scripts/upload-models.sh "$(FILE)"
else
	@echo "Usage: make upload-models FILE=path/to/model.safetensors"
	@echo "   or: make upload-models FILE=path/to/models/directory/"
endif

list-models: check-config
	@BUCKET_NAME=$$(grep '^bucket_name' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "comfy-spot-model-storage"); \
	echo "Models in bucket: gs://$$BUCKET_NAME"; \
	gsutil ls -lh "gs://$$BUCKET_NAME/**" 2>/dev/null || echo "No models found or bucket not accessible"

# Utilities
validate: check-config
	terraform validate
	terraform fmt -check

format:
	terraform fmt

clean:
	rm -rf .terraform/
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate*
	rm -f *tfplan*

# Reset backend configuration for troubleshooting
reset-backend: check-config
	@echo "⚠️  This will reset Terraform backend configuration"
	@echo "⚠️  Use this only if you're having backend issues"
	@read -p "Continue? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		$(MAKE) clean; \
		echo "ℹ️  Backend reset. Run 'make setup' to reconfigure."; \
	else \
		echo "Cancelled"; \
	fi

# Setup helper functions
_check_prerequisites:
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "🔍 [DRY-RUN] Would check Google Cloud CLI installation"; \
		echo "🔍 [DRY-RUN] Would verify project configuration"; \
		echo "🔍 [DRY-RUN] Would verify authentication"; \
		echo "✅ Prerequisites check complete (dry-run)"; \
	else \
		if ! command -v gcloud &> /dev/null; then \
			echo "❌ Google Cloud CLI (gcloud) is not installed"; \
			echo "ℹ️  Install it from: https://cloud.google.com/sdk/docs/install"; \
			exit 1; \
		fi; \
		PROJECT=$$(gcloud config get-value project 2>/dev/null || echo ""); \
		if [ -z "$$PROJECT" ]; then \
			echo "❌ No default Google Cloud project set"; \
			echo "ℹ️  Run: gcloud config set project YOUR_PROJECT_ID"; \
			exit 1; \
		fi; \
		ACCOUNT=$$(gcloud config get-value account 2>/dev/null || echo ""); \
		if [ -z "$$ACCOUNT" ]; then \
			echo "❌ Not authenticated with Google Cloud"; \
			echo "ℹ️  Run: gcloud auth login"; \
			exit 1; \
		fi; \
		echo "✅ Google Cloud CLI configured (Project: $$PROJECT, Account: $$ACCOUNT)"; \
	fi

_interactive_config:
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "🔍 [DRY-RUN] Would run interactive configuration wizard"; \
		echo "🔍 [DRY-RUN] Would create terraform.tfvars with user-provided values"; \
		echo "🔍 [DRY-RUN] Would auto-detect public IP and generate unique bucket names"; \
	else \
		$(MAKE) _interactive_config_real; \
	fi

_interactive_config_real:
	@echo "📋 Project Configuration"
	@PROJECT_ID=$$(gcloud config get-value project 2>/dev/null); \
	read -p "Google Cloud Project ID [$$PROJECT_ID]: " INPUT_PROJECT; \
	PROJECT_ID=$${INPUT_PROJECT:-$$PROJECT_ID}; \
	if [ -z "$$PROJECT_ID" ]; then \
		echo "❌ Project ID is required"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "🔐 Access Configuration"; \
	DEFAULT_EMAIL=$$(gcloud config get-value account 2>/dev/null); \
	read -p "Your email address (for SSH access) [$$DEFAULT_EMAIL]: " IAP_EMAIL; \
	IAP_EMAIL=$${IAP_EMAIL:-$$DEFAULT_EMAIL}; \
	read -p "Email for system alerts [$$IAP_EMAIL]: " NOTIF_EMAIL; \
	NOTIF_EMAIL=$${NOTIF_EMAIL:-$$IAP_EMAIL}; \
	echo ""; \
	echo "🌐 Network Configuration"; \
	DETECTED_IP=$$(curl -s -4 ifconfig.me 2>/dev/null || echo ""); \
	if [ -n "$$DETECTED_IP" ]; then \
		echo "ℹ️  Detected your public IP: $$DETECTED_IP"; \
		read -p "Use this IP for direct ComfyUI access? [Y/n]: " USE_IP; \
		if [[ $$USE_IP =~ ^[Nn] ]]; then \
			read -p "Enter your public IP address: " ALLOWED_IP; \
		else \
			ALLOWED_IP="$$DETECTED_IP"; \
		fi; \
	else \
		echo "⚠️  Could not auto-detect your public IP"; \
		echo "Get your IP from: https://whatismyip.com"; \
		read -p "Enter your public IP address: " ALLOWED_IP; \
	fi; \
	echo ""; \
	echo "🌍 Deployment Location"; \
	read -p "Google Cloud Region [us-central1]: " REGION; \
	REGION=$${REGION:-"us-central1"}; \
	read -p "Google Cloud Zone [us-central1-a]: " ZONE; \
	ZONE=$${ZONE:-"us-central1-a"}; \
	read -p "Instance name [comfy-spot-a3]: " INSTANCE_NAME; \
	INSTANCE_NAME=$${INSTANCE_NAME:-"comfy-spot-a3"}; \
	echo ""; \
	echo "💾 Storage Configuration"; \
	TIMESTamp=$$(date +%s); \
	DEFAULT_BUCKET="comfy-spot-models-$$PROJECT_ID-$$TIMESTamp"; \
	read -p "Model storage bucket name [$$DEFAULT_BUCKET]: " BUCKET_NAME; \
	BUCKET_NAME=$${BUCKET_NAME:-$$DEFAULT_BUCKET}; \
	DEFAULT_STATE_BUCKET="comfy-spot-state-$$PROJECT_ID-$$TIMESTamp"; \
	read -p "Terraform state bucket name [$$DEFAULT_STATE_BUCKET]: " STATE_BUCKET; \
	STATE_BUCKET=$${STATE_BUCKET:-$$DEFAULT_STATE_BUCKET}; \
	echo ""; \
	echo "⚡ Performance Configuration"; \
	read -p "RAM disk size [75G]: " RAM_SIZE; \
	RAM_SIZE=$${RAM_SIZE:-"75G"}; \
	read -p "ComfyUI port [8188]: " COMFY_PORT; \
	COMFY_PORT=$${COMFY_PORT:-"8188"}; \
	echo ""; \
	echo "ℹ️  Creating terraform.tfvars configuration..."; \
	{ \
		echo "# ComfyUI Spot Instance Configuration"; \
		echo "# Generated by setup wizard on $$(date)"; \
		echo ""; \
		echo "# Required Variables"; \
		echo "project_id         = \"$$PROJECT_ID\""; \
		echo "iap_user_email     = \"$$IAP_EMAIL\""; \
		echo "notification_email = \"$$NOTIF_EMAIL\""; \
		echo ""; \
		echo "# Server Location & Identity"; \
		echo "region         = \"$$REGION\""; \
		echo "zone           = \"$$ZONE\""; \
		echo "instance_name  = \"$$INSTANCE_NAME\""; \
		echo ""; \
		echo "# Server Hardware"; \
		echo "machine_type   = \"a3-highgpu-1g\""; \
		echo "boot_disk_size = 50"; \
		echo "gpu_type       = \"nvidia-h100-80gb\""; \
		echo "gpu_count      = 1"; \
		echo ""; \
		echo "# Networking"; \
		echo "network_name   = \"comfy-net\""; \
		echo "subnet_name    = \"comfy-subnet\""; \
		echo "subnet_cidr    = \"172.32.64.0/24\""; \
		echo ""; \
		echo "# Model Storage"; \
		echo "bucket_name          = \"$$BUCKET_NAME\""; \
		echo "bucket_location      = \"$$REGION\""; \
		echo "bucket_force_destroy = false"; \
		echo ""; \
		echo "# Performance & Access Configuration"; \
		echo "ram_disk_size        = \"$$RAM_SIZE\""; \
		echo "comfyui_port         = $$COMFY_PORT"; \
		echo "allowed_ip_address   = \"$$ALLOWED_IP\""; \
		echo ""; \
		echo "# Infrastructure Management"; \
		echo "terraform_state_bucket = \"$$STATE_BUCKET\""; \
	} > terraform.tfvars
	@echo "✅ Configuration saved to terraform.tfvars"

_check_billing:
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "🔍 [DRY-RUN] Would check billing configuration"; \
	else \
		PROJECT_ID=$$(grep '^project_id' terraform.tfvars | cut -d'"' -f2 2>/dev/null); \
		echo "ℹ️  Checking billing configuration..."; \
		if ! gcloud billing accounts list --format="value(name)" | head -1 > /dev/null 2>&1; then \
			echo "❌ No billing account found or insufficient permissions"; \
			echo "ℹ️  Ensure you have a billing account and 'Billing Account User' role"; \
			exit 1; \
		fi; \
		BILLING_ACCOUNT=$$(gcloud billing projects describe "$$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo ""); \
		if [ -z "$$BILLING_ACCOUNT" ]; then \
			echo "❌ Billing is not enabled for project: $$PROJECT_ID"; \
			echo "ℹ️  Enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=$$PROJECT_ID"; \
			exit 1; \
		fi; \
		echo "✅ Billing is configured for project: $$PROJECT_ID"; \
	fi

_enable_apis:
	@PROJECT_ID=$$(grep '^project_id' terraform.tfvars 2>/dev/null | cut -d'"' -f2 || gcloud config get-value project 2>/dev/null); \
	APIS="compute.googleapis.com storage.googleapis.com iam.googleapis.com monitoring.googleapis.com logging.googleapis.com serviceusage.googleapis.com"; \
	for API in $$APIS; do \
		echo "ℹ️  Enabling $$API..."; \
		if [ "$(DRY_RUN)" = "true" ]; then \
			echo "🔍 [DRY-RUN] Would enable API: $$API"; \
		else \
			if gcloud services enable "$$API" --project="$$PROJECT_ID" --quiet 2>/dev/null; then \
				echo "✅ $$API enabled"; \
			else \
				if gcloud services list --enabled --project="$$PROJECT_ID" --filter="name:$$API" --format="value(name)" | grep -q "$$API" 2>/dev/null; then \
					echo "✅ $$API already enabled"; \
				else \
					echo "❌ Failed to enable $$API"; \
					echo "ℹ️  Make sure you have 'Service Usage Admin' role"; \
					exit 1; \
				fi; \
			fi; \
		fi; \
	done
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "🔍 [DRY-RUN] Would wait 10 seconds for APIs to propagate"; \
	else \
		echo "ℹ️  Waiting 10 seconds for APIs to propagate..."; \
		sleep 10; \
	fi
	@echo "✅ All APIs enabled successfully"

_setup_backend:
	@if [ "$(DRY_RUN)" = "true" ]; then \
		BUCKET_NAME=$$(grep '^terraform_state_bucket' terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "[bucket-name-from-config]"); \
		REGION=$$(grep '^region' terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "[region-from-config]"); \
		echo "🔍 [DRY-RUN] Would create Terraform state bucket: $$BUCKET_NAME"; \
		echo "🔍 [DRY-RUN] Would run: gcloud storage buckets create gs://$$BUCKET_NAME --location=$$REGION"; \
		echo "🔍 [DRY-RUN] Would enable object versioning for state recovery"; \
		echo "🔍 [DRY-RUN] Would initialize Terraform directly with remote backend"; \
		echo "🔍 [DRY-RUN] Would run: terraform init -backend-config=\"bucket=$$BUCKET_NAME\""; \
		echo "✅ Remote state backend setup complete! (dry-run)"; \
		echo "ℹ️  Would use state bucket: gs://$$BUCKET_NAME"; \
	else \
		echo "ℹ️  Setting up Terraform remote state backend..."; \
		BUCKET_NAME=$$(grep '^terraform_state_bucket' terraform.tfvars | cut -d'"' -f2 2>/dev/null); \
		REGION=$$(grep '^region' terraform.tfvars | cut -d'"' -f2 2>/dev/null); \
		PROJECT_ID=$$(grep '^project_id' terraform.tfvars | cut -d'"' -f2 2>/dev/null); \
		if [ -z "$$BUCKET_NAME" ]; then \
			echo "❌ terraform_state_bucket not found in terraform.tfvars"; \
			exit 1; \
		fi; \
		if [ -z "$$REGION" ]; then \
			echo "❌ region not found in terraform.tfvars"; \
			exit 1; \
		fi; \
		echo "ℹ️  Creating Terraform state bucket: $$BUCKET_NAME in region $$REGION"; \
		if ! gcloud storage buckets describe "gs://$$BUCKET_NAME" >/dev/null 2>&1; then \
			echo "ℹ️  Bucket does not exist, creating..."; \
			gcloud storage buckets create "gs://$$BUCKET_NAME" \
				--location="$$REGION" \
				--uniform-bucket-level-access \
				--project="$$PROJECT_ID"; \
			echo "ℹ️  Enabling object versioning for state recovery..."; \
			gcloud storage buckets update "gs://$$BUCKET_NAME" --versioning; \
			echo "✅ Terraform state bucket created successfully"; \
		else \
			echo "ℹ️  Bucket $$BUCKET_NAME already exists, skipping creation"; \
		fi; \
		echo "ℹ️  Initializing Terraform with remote backend..."; \
		terraform init -backend-config="bucket=$$BUCKET_NAME"; \
		echo "✅ Remote state backend setup complete!"; \
		echo "ℹ️  State bucket: gs://$$BUCKET_NAME"; \
	fi

_validate_config:
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "🔍 [DRY-RUN] Would validate Terraform configuration"; \
		echo "✅ Terraform configuration is valid! (dry-run)"; \
	else \
		echo "ℹ️  Validating Terraform configuration..."; \
		if terraform validate; then \
			echo "✅ Terraform configuration is valid!"; \
		else \
			echo "❌ Terraform configuration validation failed"; \
			exit 1; \
		fi; \
	fi

# Quick start guide
quick-start:
	@echo "🚀 ComfySpotMgr Quick Start"
	@echo "==========================="
	@echo ""
	@echo "First time setup:"
	@echo "  make setup         # Interactive configuration"
	@echo "  make apply         # Deploy infrastructure"
	@echo ""
	@echo "Daily workflow:"
	@echo "  make start         # Create/start instance"
	@echo "  make forward       # Access at http://localhost:8188"
	@echo "  [Use ComfyUI for your projects]"
	@echo "  make destroy-vm    # Destroy instance when done"
	@echo ""
	@echo "💡 Storage (models) persists across instance recreations."
	@echo "💰 Spot instances save ~70% on compute costs."

workflow-demo: quick-start
