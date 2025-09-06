# ComfySpotMgr

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Status](https://img.shields.io/badge/Status-Beta-orange)
![Work in Progress](https://img.shields.io/badge/WIP-Components-yellow)

**ComfyUI Spot Deployment Manager** - Deploy high-performance ComfyUI instances on Google Cloud Platform with **~70% cost savings** using spot instances, NVIDIA H100 GPUs, and ultra-fast RAM disk optimization.

**✨ One-command setup wizard handles everything automatically!**

## 🚧 Work in Progress Notice

**Current Status: Beta Release**

This project is actively under development. The core functionality is stable and tested, but some features are still being implemented.

### ✅ Stable Features
- Core Terraform infrastructure deployment
- Spot instance management with H100 GPUs
- RAM disk optimization for models
- Security with Shielded VMs and IAP access
- Model upload and management scripts
- One-command setup wizard

### 🚧 In Development
- **Documentation**: More detailed setup guides (planned)
- **Examples**: Sample configurations for different use cases
- **Configuration Templates**: Pre-made setups for common scenarios
- **Optional Modules**: Reusable components (maybe future)

### ⚠️ Known Limitations
- Single-region only (multi-region not planned - this is a hobby project!)
- No automated backup/restore (you manage your own models)
- Basic monitoring only (sufficient for personal use)
- Manual cost management (check your GCP billing!)

**Ready for Personal Use?** ✅ Yes! Works great for hobbyists and individual artists  
**Need Help?** Check the troubleshooting section below or open an issue

## 🗺️ Development Ideas

### 📋 Maybe Next (when I have time!)
- [ ] **Better Docs**: More detailed guides in the docs directory
- [ ] **Config Examples**: Sample setups for different use cases  
- [ ] **Cost Templates**: Pre-configured cheap/balanced/performance options
- [ ] **Regional Options**: Easy region switching (US/EU/Asia)

### 🔮 Someday Ideas (no promises!)
- [ ] **Monitoring Dashboard**: Simple cost and usage tracking
- [ ] **Model Recommendations**: Suggestions for different art styles
- [ ] **One-Click Workflows**: Common ComfyUI workflow templates
- [ ] **Community Sharing**: Share configurations with other hobbyists

**This is a hobby project!** Features get added when I have time and motivation. Want to help? PRs welcome!

**Want to contribute?** Check our [issues](https://github.com/DataSparBrian/comfy-spot-deploy/issues) or suggest new features!

## Project Structure

```
├── Makefile              # All management commands (simplified!) ✅
├── terraform/            # Terraform infrastructure code ✅
│   ├── *.tf              # Terraform configuration files
│   ├── terraform.tfvars  # Your configuration (created by setup)
│   ├── environments/    # 🚧 Maybe: Different config templates  
│   └── modules/         # 🚧 Maybe: Reusable components (if needed)
├── scripts/             # Utility scripts ✅
│   ├── manage-instance.sh # Instance lifecycle management
│   ├── upload-models.sh  # Model upload utility
│   └── grant-permissions.sh # Permission setup script
├── docs/               # 🚧 Someday: Better documentation (when motivated!)
├── examples/          # 🚧 Maybe: Sample configs for different use cases
└── README.md         # This file ✅
```

**Legend:** ✅ Complete | 🚧 Work in Progress | ❌ Planned

## Architecture

ComfySpotMgr uses a sophisticated **multi-tier caching architecture** for maximum performance and resilience:

### 🚀 Multi-Tier Caching System
```
RAM Disk (75GB) → Local SSD Cache → Hyperdisk Persistent (300GB) → GCS Bucket
   ↑ Active         ↑ ~30s Recovery    ↑ Zone-Resilient Cache    ↑ Model Storage
```

**Performance Benefits:**
- **~30 second startup** when Local SSD cache is available (after first run)
- **~60-90 second startup** when recovering from Hyperdisk cache  
- **Fresh installation only** when no cache exists (~5-10 minutes)
- **Automatic cache population** during background operation

### 🏗️ Infrastructure Components
- **Spot VM Instance**: A3-highgpu-1g with NVIDIA H100 80GB GPU running on GCP spot pricing  
- **RAM Disk Performance**: Configurable RAM disk (default 75GB) for ultra-fast ComfyUI and model access
- **Multi-Tier Storage**: 
  - **Local SSD Cache**: Boot disk cache for fastest recovery
  - **Hyperdisk Balanced**: 300GB persistent cache surviving instance recreation
  - **GCS Bucket**: Model storage and final backup layer
- **Security**: Shielded VM with secure boot, vTPM, and integrity monitoring
- **Access Control**: IAP SSH access + configurable IP allowlist for web interface
- **Monitoring**: Proactive alerting for integrity failures and cache status

### 🔄 Cache Intelligence
- **Smart Detection**: Automatically finds fastest available cache layer
- **Background Sync**: Continuous 5-minute intervals sync RAM disk to cache layers  
- **Shutdown Preservation**: Graceful shutdown hooks save state before termination
- **Cache Validation**: Integrity checks ensure reliable recovery
- **Zone Resilience**: Hyperdisk cache survives instance recreation and zone failures

## 🚀 Quick Start

ComfySpotMgr provides automated deployment and management of ComfyUI instances on Google Cloud spot instances.

### Prerequisites

Before using ComfySpotMgr, ensure you have:
- Google Cloud Project with billing enabled
- Terraform installed (`brew install terraform` on macOS) 
- `gcloud` CLI installed and authenticated (`gcloud auth login`)

### 🔐 Critical Security Setup

**IMPORTANT**: For security best practices, use separate accounts for admin setup vs. day-to-day operations:

1. **Admin Account Setup** (run once with project owner/admin privileges):
   ```bash
   # Switch to your admin account
   gcloud auth login admin@yourdomain.com
   
   # Grant minimal required permissions to your regular user account
   ./scripts/grant-permissions.sh your-regular-user@yourdomain.com your-project-id
   ```

2. **Regular User Operations** (use your day-to-day account):
   ```bash
   # Switch to your regular user account (with limited permissions)
   gcloud auth login your-regular-user@yourdomain.com
   
   # Now proceed with ComfySpotMgr setup
   make setup
   ```

**Why this matters**: This follows the principle of least privilege - your daily-use account only gets the minimal permissions needed for ComfySpotMgr operations, while keeping admin privileges separate.

### 🎯 One-Command Setup

ComfySpotMgr includes an interactive setup wizard that handles everything:

```bash
# Interactive setup wizard - handles everything!
make setup

# Preview what setup would do (without making changes)
make setup-dry-run
```

The setup wizard will:
- ✅ Validate your Google Cloud configuration
- ✅ Auto-detect your public IP address
- ✅ Enable all required APIs
- ✅ Generate unique bucket names
- ✅ Create terraform.tfvars with your settings
- ✅ Set up Terraform remote state backend

### Deploy Your Instance

```bash
# Review what will be created
make plan

# Deploy the infrastructure
make apply
```

### 🎨 Access ComfyUI

**Easy Port Forward (recommended):**
```bash
# Forward ComfyUI to your local machine
make forward
```
Then open http://localhost:8188 in your browser

**Direct Access:**
If configured during setup, access directly at `http://[INSTANCE_IP]:8188`

**SSH Access:**
```bash
# SSH into the instance
make ssh
```

## ⚙️ Configuration

The setup wizard creates `terraform/terraform.tfvars` with all necessary settings. You can manually edit it later if needed:

```hcl
# Core Configuration
project_id         = "your-gcp-project"     # Your GCP project ID
iap_user_email     = "user@example.com"     # Email for SSH access
allowed_ip_address = "1.2.3.4"             # Your public IP (auto-detected)

# Instance Settings
machine_type    = "a3-highgpu-1g"           # A3 instance with H100 GPU
ram_disk_size   = "75G"                     # Ultra-fast model storage
region         = "us-central1"              # Deployment location

# Storage
bucket_name     = "your-models-bucket"      # Auto-generated unique name
```

**All settings are configured by ComfySpotMgr during setup - no manual editing required!**

## 🚀 Cache Management

ComfySpotMgr's multi-tier caching system dramatically improves startup times after the first deployment.

### 📊 Cache Behavior
- **First Deployment**: Fresh installation (~5-10 minutes) + automatic cache population
- **Subsequent Deployments**: 
  - **Local SSD Hit**: ~30 second recovery
  - **Hyperdisk Hit**: ~60-90 second recovery  
  - **Cache Miss**: Falls back to fresh installation

### 🔧 Cache Commands
```bash
# Check cache status via SSH
make ssh
sudo ls -la /opt/comfyui_cache/        # Local SSD cache
sudo ls -la /mnt/persistent/           # Hyperdisk cache

# View background sync logs
make ssh
sudo tail -f /var/log/comfy-sync.log

# Monitor cache validation during startup
make logs
```

### 🔄 Cache Sync Settings
The system syncs every **5 minutes** by default:
- **RAM Disk** → **Local SSD Cache** (for faster next startup)
- **RAM Disk** → **Hyperdisk Cache** (for zone resilience)
- **Shutdown sync** preserves final state

### 🧹 Cache Management
```bash
# Clear local cache (forces Hyperdisk or fresh install recovery)
make ssh
sudo rm -rf /opt/comfyui_cache/

# Clear persistent cache (forces fresh install - use carefully!)
make ssh  
sudo rm -rf /mnt/persistent/comfyui_cache/

# Force fresh installation (disables all caching temporarily)
# Edit terraform.tfvars: enable_persistent_cache = false
make apply
```

**Pro Tip:** The caching system is automatic and self-managing. Manual intervention is rarely needed!

## 🎨 Model Management

### Adding Models
```bash
# Upload models using the built-in script
make upload-models FILE=path/to/your-model.safetensors

# List current models
make list-models

# Restart instance to load new models into RAM disk
make restart
```

### Supported Model Types
- `checkpoints/` - Base models (SDXL, SD1.5, etc.)
- `loras/` - LoRA adapters
- `vae/` - VAE models
- `controlnet/` - ControlNet models
- `clip/` - CLIP models
- `unet/` - UNet models

## 💰 Cost Optimization

### Spot Instance Benefits
- **~70% cost savings** compared to regular instances
- Automatic termination when GCP needs capacity
- Perfect for experimentation and development

### Managing Costs
```bash
# Stop instance when not in use
make stop

# Start when needed  
make start

# Destroy instance but keep models
make destroy-vm

# Check instance status
make status
```

**Pro Tip:** Use `make destroy-vm` between sessions to minimize costs while keeping your models in cloud storage!

## 🔧 Troubleshooting

### Quick Diagnostics
```bash
# Check instance status
make status

# View startup logs
make logs

# SSH into instance for debugging
make ssh
```

### Common Issues

**ComfyUI Not Accessible:**
- Run `make forward` and access http://localhost:8188
- Check your IP address hasn't changed (re-run `make setup` if needed)

**Models Not Loading:**
- Verify models uploaded: `make list-models`
- Restart instance: `make restart`

**Instance Won't Start:**
- Check logs: `make logs`
- Verify billing and quotas in Google Cloud Console

**Deep Learning VM Image Issues:**
- ComfySpotMgr uses the current supported Google Cloud Deep Learning VM image: `pytorch-2-7-cu128-ubuntu-2204-nvidia-570`
- This provides PyTorch 2.7, CUDA 12.8, Ubuntu 22.04, and NVIDIA driver 570
- Image selection is now simplified and robust (no complex fallback logic needed)

## Security Considerations

### 🔐 Account Separation (Critical)
- **Admin vs. User Accounts**: Use `grant-permissions.sh` to set up minimal permissions for daily operations
- **Principle of Least Privilege**: Regular user account gets only necessary roles (Compute Admin, Storage Admin, etc.)
- **No Standing Admin Access**: Keep admin privileges separate from day-to-day deployment account

### 🛡️ Infrastructure Security
- **Shielded VM**: Hardware-level security with secure boot, vTPM, and integrity monitoring
- **IAP Access**: SSH access through Identity-Aware Proxy (no direct SSH exposure)
- **Private Networking**: Custom VPC with controlled subnet and firewall rules
- **Service Account**: Dedicated service account with least-privilege GCS permissions
- **IP Allowlist**: Configurable IP restrictions for web interface access
- **Spot Instance Isolation**: Temporary compute with persistent encrypted storage

## 🔬 Advanced Usage

### Multiple Regions
Re-run setup wizard with different region/zone for multi-region deployments

### Custom Configuration
Edit `terraform/terraform.tfvars` after initial setup to customize:
- Instance types and GPU configurations
- Network settings and security rules
- Storage and performance parameters

### Model Persistence
Models are automatically stored in Google Cloud Storage and copied to ultra-fast RAM disk at startup for maximum performance.

## 🧹 Cleanup

```bash
# Destroy everything (keeps model storage by default)
make destroy

# Or just destroy the expensive compute instance
make destroy-vm
```

**Note**: Model storage is preserved by default to protect your data.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Dependencies

This deployment tool helps you run ComfyUI and other software components:

- **ComfyUI**: GPL-3.0 licensed (deployed application)
- **Terraform**: MPL-2.0 licensed (infrastructure automation)
- **Google Cloud Platform**: Commercial cloud services

The MIT license applies to the deployment automation scripts and infrastructure code in this repository, providing maximum flexibility for users while maintaining compatibility with all dependencies.

## Support

- Check the [ComfyUI documentation](https://github.com/comfyanonymous/ComfyUI)
- Review [Terraform Google provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- For infrastructure issues, check the startup script logs via SSH
