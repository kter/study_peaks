.PHONY: help flutter-get flutter-analyze flutter-run flutter-build \
        tf-init tf-validate tf-dev-plan tf-dev-apply tf-prd-plan tf-prd-apply \
        tf-workspace-dev tf-workspace-prd

# Default target
help:
	@echo "Global Study Peaks - Makefile Commands"
	@echo ""
	@echo "Flutter:"
	@echo "  make flutter-get       - Install dependencies"
	@echo "  make flutter-analyze   - Run static analysis"
	@echo "  make flutter-run       - Run on connected device"
	@echo "  make flutter-build-apk - Build Android APK"
	@echo ""
	@echo "Terraform:"
	@echo "  make tf-init           - Initialize Terraform"
	@echo "  make tf-validate       - Validate configuration"
	@echo "  make tf-workspace-dev  - Switch to dev workspace"
	@echo "  make tf-workspace-prd  - Switch to prd workspace"
	@echo "  make tf-dev-plan       - Plan dev environment"
	@echo "  make tf-dev-apply      - Apply dev environment"
	@echo "  make tf-prd-plan       - Plan prd environment"
	@echo "  make tf-prd-apply      - Apply prd environment"

# ============================================
# Flutter Commands
# ============================================

flutter-get:
	flutter pub get

flutter-analyze:
	flutter analyze

flutter-run:
	flutter run

flutter-build-apk:
	flutter build apk --release

flutter-build-aab:
	flutter build appbundle --release

flutter-test:
	flutter test

# ============================================
# Terraform Commands
# ============================================

TERRAFORM_DIR := terraform

tf-init:
	cd $(TERRAFORM_DIR) && terraform init

tf-validate:
	cd $(TERRAFORM_DIR) && terraform validate

tf-fmt:
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

# Workspace management
tf-workspace-dev:
	cd $(TERRAFORM_DIR) && terraform workspace select dev || terraform workspace new dev

tf-workspace-prd:
	cd $(TERRAFORM_DIR) && terraform workspace select prd || terraform workspace new prd

# Dev environment
tf-dev-plan: tf-workspace-dev
	cd $(TERRAFORM_DIR) && terraform plan -var-file="env/dev.tfvars"

tf-dev-apply: tf-workspace-dev
	cd $(TERRAFORM_DIR) && terraform apply -var-file="env/dev.tfvars"

tf-dev-destroy: tf-workspace-dev
	cd $(TERRAFORM_DIR) && terraform destroy -var-file="env/dev.tfvars"

# Prd environment
tf-prd-plan: tf-workspace-prd
	cd $(TERRAFORM_DIR) && terraform plan -var-file="env/prd.tfvars"

tf-prd-apply: tf-workspace-prd
	cd $(TERRAFORM_DIR) && terraform apply -var-file="env/prd.tfvars"

# Show current state
tf-show:
	cd $(TERRAFORM_DIR) && terraform workspace show && terraform output
