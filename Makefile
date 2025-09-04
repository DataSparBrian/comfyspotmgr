# ComfySpotMgr - ComfyUI Spot Deployment Manager
# Root Makefile - delegates to terraform/

# Default target is help

# Explicit targets for common commands  
.PHONY: setup setup-dry-run plan apply destroy start stop status ssh forward logs upload-models clean help grant-permissions

help:
	@echo ""
	@echo "================================================="
	@echo "🚀 ComfySpotMgr - ComfyUI Spot Deployment Manager"
	@echo "================================================="
	@echo ""
	@echo "All commands are delegated to terraform/Makefile"
	@echo ""
	@echo "Security Setup (run with admin account):"
	@echo "  make grant-permissions - Grant permissions to user account"
	@echo ""
	@echo "Quick Start:"
	@echo "  make setup         - Interactive setup wizard"
	@echo "  make plan          - Show Terraform plan"
	@echo "  make apply         - Deploy infrastructure"
	@echo ""
	@echo "Instance Management:"
	@echo "  make start         - Start instance"
	@echo "  make stop          - Stop instance"
	@echo "  make status        - Check status"
	@echo ""
	@echo "Access:"
	@echo "  make ssh           - SSH to instance"
	@echo "  make forward       - Port forward ComfyUI"
	@echo ""
	@echo "For full help:"
	@echo "  cd terraform && make help"
	@echo ""
	@echo "================================================="
	@echo ""

setup:
	@$(MAKE) -C terraform setup

setup-dry-run:
	@$(MAKE) -C terraform setup-dry-run

plan:
	@$(MAKE) -C terraform plan

apply:
	@$(MAKE) -C terraform apply

destroy:
	@$(MAKE) -C terraform destroy

# Security command - grant permissions
grant-permissions:
	@./scripts/grant-permissions.sh

# Delegate specific commands to terraform/Makefile
start stop status ssh forward logs upload-models clean validate list-models restart destroy-vm quick-start workflow-demo:
	@$(MAKE) -C terraform $@