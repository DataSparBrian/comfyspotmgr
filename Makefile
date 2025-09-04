# ComfySpotMgr - ComfyUI Spot Deployment Manager
# Simplified consolidated Makefile

.PHONY: help setup setup-dry-run plan apply destroy start stop restart status destroy-vm ssh forward logs upload-models list-models validate format clean reset-backend grant-permissions quick-start

# Default target
.DEFAULT_GOAL := help

# ============================================================================
# HELP AND INFORMATION
# ============================================================================

help:
	@echo ""
	@echo "================================================="
	@echo "🚀 ComfySpotMgr - ComfyUI Spot Deployment Manager"
	@echo "================================================="
	@echo ""
	@echo "🏁 Quick Start:"
	@echo "  setup         - Interactive setup wizard (run this first!)"
	@echo "  plan          - Show Terraform execution plan"
	@echo "  apply         - Deploy infrastructure"
	@echo "  start         - Start ComfyUI instance"
	@echo "  forward       - Access ComfyUI at http://localhost:8188"
	@echo ""
	@echo "📦 Deployment:"
	@echo "  setup-dry-run - Preview setup without making changes"
	@echo "  plan          - Show Terraform execution plan"
	@echo "  apply         - Deploy infrastructure"
	@echo "  destroy       - Destroy all infrastructure"
	@echo ""
	@echo "⚡ Instance Management:"
	@echo "  start         - Start or create the ComfyUI instance"
	@echo "  stop          - Stop the instance (saves costs)"
	@echo "  restart       - Stop and start the instance"
	@echo "  status        - Show instance status"
	@echo "  destroy-vm    - Destroy just the VM (keeps storage)"
	@echo ""
	@echo "🔧 Development:"
	@echo "  ssh           - SSH into the instance"
	@echo "  forward       - Forward ComfyUI port to localhost"
	@echo "  logs          - View startup script logs"
	@echo ""
	@echo "📁 Model Management:"
	@echo "  upload-models - Upload models (usage: make upload-models FILE=model.safetensors)"
	@echo "  list-models   - List models in GCS bucket"
	@echo ""
	@echo "🛠️  Utilities:"
	@echo "  validate      - Validate Terraform configuration"
	@echo "  format        - Format Terraform files"
	@echo "  clean         - Clean Terraform cache files"
	@echo "  reset-backend - Reset backend configuration"
	@echo ""
	@echo "🔐 Security:"
	@echo "  grant-permissions - Grant permissions to user account"
	@echo ""

quick-start:
	@echo "🚀 ComfySpotMgr Quick Start Guide"
	@echo "================================="
	@echo ""
	@echo "First time setup:"
	@echo "  1. make setup         # Interactive configuration"
	@echo "  2. make apply         # Deploy infrastructure"
	@echo ""
	@echo "Daily workflow:"
	@echo "  3. make start         # Create/start instance"
	@echo "  4. make forward       # Access at http://localhost:8188"
	@echo "  5. [Use ComfyUI for your projects]"
	@echo "  6. make destroy-vm    # Destroy instance when done"
	@echo ""
	@echo "💡 Storage (models) persists across instance recreations"
	@echo "💰 Spot instances save ~70% on compute costs"

# ============================================================================
# CONFIGURATION AND SETUP
# ============================================================================

# Check if terraform.tfvars exists
check-config:
	@if [ ! -f terraform/terraform.tfvars ]; then \
		echo "❌ terraform/terraform.tfvars not found!"; \
		echo "Run 'make setup' to create your configuration."; \
		exit 1; \
	fi

# Interactive setup wizard
setup:
	@echo "🚀 Starting ComfySpotMgr setup wizard..."
	@$(MAKE) _check_prerequisites
	@$(MAKE) _interactive_config
	@$(MAKE) _check_billing
	@$(MAKE) _enable_apis
	@$(MAKE) _setup_backend
	@$(MAKE) _validate_config
	@echo ""
	@echo "🎉 Setup Complete!"
	@echo "=================="
	@echo ""
	@echo "✅ Your ComfySpotMgr deployment is ready!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Review the plan:    make plan"
	@echo "  2. Deploy:             make apply"
	@echo "  3. Access ComfyUI:     make forward"

setup-dry-run:
	@echo "🔍 ComfySpotMgr setup wizard (DRY-RUN MODE)"
	@echo "⚠️  This is a dry-run - no changes will be made"
	@echo ""
	@echo "✅ Prerequisites would be checked"
	@echo "✅ Interactive configuration would run"
	@echo "✅ Billing would be validated"
	@echo "✅ Google Cloud APIs would be enabled"
	@echo "✅ Terraform backend would be configured"
	@echo "✅ Configuration would be validated"
	@echo ""
	@echo "To execute for real: make setup"

# ============================================================================
# TERRAFORM OPERATIONS
# ============================================================================

plan: check-config
	@cd terraform && terraform plan -var-file="terraform.tfvars"

apply: check-config
	@cd terraform && terraform apply -var-file="terraform.tfvars"

destroy: check-config
	@echo "⚠️  WARNING: This will destroy ALL infrastructure!"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		cd terraform && terraform destroy -var-file="terraform.tfvars"; \
	else \
		echo "Cancelled"; \
	fi

validate: check-config
	@cd terraform && terraform validate && terraform fmt -check

format:
	@cd terraform && terraform fmt

# ============================================================================
# INSTANCE MANAGEMENT
# ============================================================================

start:
	@./scripts/manage-instance.sh start

stop:
	@./scripts/manage-instance.sh stop

restart: stop
	@sleep 5
	@$(MAKE) start

status:
	@./scripts/manage-instance.sh status

destroy-vm:
	@./scripts/manage-instance.sh destroy

# ============================================================================
# DEVELOPMENT AND ACCESS
# ============================================================================

ssh:
	@./scripts/manage-instance.sh ssh

forward:
	@./scripts/manage-instance.sh forward

logs:
	@./scripts/manage-instance.sh logs

# ============================================================================
# MODEL MANAGEMENT
# ============================================================================

upload-models:
ifdef FILE
	@./scripts/upload-models.sh "$(FILE)"
else
	@echo "Usage: make upload-models FILE=path/to/model.safetensors"
	@echo "   or: make upload-models FILE=path/to/models/directory/"
endif

list-models: check-config
	@BUCKET_NAME=$$(grep '^bucket_name' terraform/terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "comfy-spot-model-storage"); \
	echo "Models in bucket: gs://$$BUCKET_NAME"; \
	gsutil ls -lh "gs://$$BUCKET_NAME/**" 2>/dev/null || echo "No models found or bucket not accessible"

# ============================================================================
# UTILITIES
# ============================================================================

clean:
	@cd terraform && rm -rf .terraform/ .terraform.lock.hcl terraform.tfstate* *tfplan*
	@echo "✅ Terraform cache files cleaned"

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

grant-permissions:
	@./scripts/grant-permissions.sh $(filter-out $@,$(MAKECMDGOALS))

# Prevent Make from treating arguments as targets
%:
	@:

# ============================================================================
# INTERNAL SETUP FUNCTIONS
# ============================================================================

_check_prerequisites:
	@echo "Step 1: Checking prerequisites..."
	@if ! command -v gcloud &> /dev/null; then \
		echo "❌ Google Cloud CLI (gcloud) is not installed"; \
		echo "ℹ️  Install it from: https://cloud.google.com/sdk/docs/install"; \
		exit 1; \
	fi
	@PROJECT=$$(gcloud config get-value project 2>/dev/null || echo ""); \
	if [ -z "$$PROJECT" ]; then \
		echo "❌ No default Google Cloud project set"; \
		echo "ℹ️  Run: gcloud config set project YOUR_PROJECT_ID"; \
		exit 1; \
	fi
	@ACCOUNT=$$(gcloud config get-value account 2>/dev/null || echo ""); \
	if [ -z "$$ACCOUNT" ]; then \
		echo "❌ Not authenticated with Google Cloud"; \
		echo "ℹ️  Run: gcloud auth login"; \
		exit 1; \
	fi
	@echo "✅ Google Cloud CLI configured (Project: $$PROJECT, Account: $$ACCOUNT)"

_interactive_config:
	@echo ""
	@echo "Step 2: Configuring deployment..."
	@PROJECT_ID=$$(gcloud config get-value project 2>/dev/null); \
	read -p "Google Cloud Project ID [$$PROJECT_ID]: " INPUT_PROJECT; \
	PROJECT_ID=$${INPUT_PROJECT:-$$PROJECT_ID}; \
	DEFAULT_EMAIL=$$(gcloud config get-value account 2>/dev/null); \
	read -p "Your email address (for SSH access) [$$DEFAULT_EMAIL]: " IAP_EMAIL; \
	IAP_EMAIL=$${IAP_EMAIL:-$$DEFAULT_EMAIL}; \
	read -p "Email for system alerts [$$IAP_EMAIL]: " NOTIF_EMAIL; \
	NOTIF_EMAIL=$${NOTIF_EMAIL:-$$IAP_EMAIL}; \
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
		read -p "Enter your public IP address: " ALLOWED_IP; \
	fi; \
	read -p "Google Cloud Region [us-central1]: " REGION; \
	REGION=$${REGION:-"us-central1"}; \
	read -p "Google Cloud Zone [us-central1-a]: " ZONE; \
	ZONE=$${ZONE:-"us-central1-a"}; \
	read -p "Instance name [comfy-spot-a3]: " INSTANCE_NAME; \
	INSTANCE_NAME=$${INSTANCE_NAME:-"comfy-spot-a3"}; \
	TIMESTAMP=$$(date +%s); \
	DEFAULT_BUCKET="comfy-spot-models-$$PROJECT_ID-$$TIMESTAMP"; \
	read -p "Model storage bucket name [$$DEFAULT_BUCKET]: " BUCKET_NAME; \
	BUCKET_NAME=$${BUCKET_NAME:-$$DEFAULT_BUCKET}; \
	DEFAULT_STATE_BUCKET="comfy-spot-state-$$PROJECT_ID-$$TIMESTAMP"; \
	read -p "Terraform state bucket name [$$DEFAULT_STATE_BUCKET]: " STATE_BUCKET; \
	STATE_BUCKET=$${STATE_BUCKET:-$$DEFAULT_STATE_BUCKET}; \
	mkdir -p terraform; \
	{ \
		echo "# ComfyUI Spot Instance Configuration"; \
		echo "# Generated by setup wizard on $$(date)"; \
		echo ""; \
		echo "project_id         = \"$$PROJECT_ID\""; \
		echo "iap_user_email     = \"$$IAP_EMAIL\""; \
		echo "notification_email = \"$$NOTIF_EMAIL\""; \
		echo "region             = \"$$REGION\""; \
		echo "zone               = \"$$ZONE\""; \
		echo "instance_name      = \"$$INSTANCE_NAME\""; \
		echo "machine_type       = \"a3-highgpu-1g\""; \
		echo "boot_disk_size     = 50"; \
		echo "gpu_type           = \"nvidia-h100-80gb\""; \
		echo "gpu_count          = 1"; \
		echo "network_name       = \"comfy-net\""; \
		echo "subnet_name        = \"comfy-subnet\""; \
		echo "subnet_cidr        = \"172.32.64.0/24\""; \
		echo "bucket_name        = \"$$BUCKET_NAME\""; \
		echo "bucket_location    = \"$$REGION\""; \
		echo "bucket_force_destroy = false"; \
		echo "ram_disk_size      = \"75G\""; \
		echo "comfyui_port       = 8188"; \
		echo "allowed_ip_address = \"$$ALLOWED_IP\""; \
		echo "terraform_state_bucket = \"$$STATE_BUCKET\""; \
	} > terraform/terraform.tfvars; \
	echo "✅ Configuration saved to terraform/terraform.tfvars"

_check_billing:
	@echo ""
	@echo "Step 3: Validating billing..."
	@PROJECT_ID=$$(grep '^project_id' terraform/terraform.tfvars | cut -d'"' -f2 2>/dev/null); \
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
	echo "✅ Billing is configured for project: $$PROJECT_ID"

_enable_apis:
	@echo ""
	@echo "Step 4: Enabling Google Cloud APIs..."
	@PROJECT_ID=$$(grep '^project_id' terraform/terraform.tfvars | cut -d'"' -f2); \
	APIS="compute.googleapis.com storage.googleapis.com iam.googleapis.com monitoring.googleapis.com logging.googleapis.com serviceusage.googleapis.com"; \
	for API in $$APIS; do \
		echo "ℹ️  Enabling $$API..."; \
		if gcloud services enable "$$API" --project="$$PROJECT_ID" --quiet 2>/dev/null || \
		   gcloud services list --enabled --project="$$PROJECT_ID" --filter="name:$$API" --format="value(name)" | grep -q "$$API" 2>/dev/null; then \
			echo "✅ $$API enabled"; \
		else \
			echo "❌ Failed to enable $$API"; \
			exit 1; \
		fi; \
	done; \
	echo "ℹ️  Waiting for APIs to propagate..."; \
	sleep 10; \
	echo "✅ All APIs enabled successfully"

_setup_backend:
	@echo ""
	@echo "Step 5: Setting up Terraform backend..."
	@BUCKET_NAME=$$(grep '^terraform_state_bucket' terraform/terraform.tfvars | cut -d'"' -f2); \
	REGION=$$(grep '^region' terraform/terraform.tfvars | cut -d'"' -f2); \
	PROJECT_ID=$$(grep '^project_id' terraform/terraform.tfvars | cut -d'"' -f2); \
	if ! gcloud storage buckets describe "gs://$$BUCKET_NAME" >/dev/null 2>&1; then \
		echo "ℹ️  Creating Terraform state bucket: $$BUCKET_NAME"; \
		gcloud storage buckets create "gs://$$BUCKET_NAME" \
			--location="$$REGION" \
			--uniform-bucket-level-access \
			--project="$$PROJECT_ID"; \
		gcloud storage buckets update "gs://$$BUCKET_NAME" --versioning; \
		echo "✅ Terraform state bucket created"; \
	else \
		echo "ℹ️  State bucket already exists"; \
	fi; \
	cd terraform && terraform init -backend-config="bucket=$$BUCKET_NAME"; \
	echo "✅ Remote state backend setup complete"

_validate_config:
	@echo ""
	@echo "Step 6: Validating Terraform configuration..."
	@cd terraform && terraform validate
	@echo "✅ Terraform configuration is valid"
