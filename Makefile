.PHONY: help flutter-get flutter-analyze flutter-run flutter-build \
        tf-init tf-validate tf-dev-plan tf-dev-apply tf-prd-plan tf-prd-apply \
        tf-workspace-dev tf-workspace-prd \
        api-build api-push api-deploy api-run

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
	@echo "Backend API:"
	@echo "  make api-build         - Build Docker image"
	@echo "  make api-push          - Push to Artifact Registry (prd)"
	@echo "  make api-deploy        - Build, push, and deploy to Cloud Run"
	@echo "  make api-run           - Run API locally"
	@echo ""
	@echo "Terraform:"
	@echo "  make tf-init           - Initialize Terraform"
	@echo "  make tf-validate       - Validate configuration"
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
# Backend API Commands
# ============================================

API_DIR := api
API_IMAGE := asia-northeast1-docker.pkg.dev/studypeaks-prd/study-peaks/api
API_TAG := v1

api-tidy:
	cd $(API_DIR) && go mod tidy

api-build:
	docker buildx build --platform linux/amd64 -t $(API_IMAGE):$(API_TAG) $(API_DIR)

api-push: api-build
	docker push $(API_IMAGE):$(API_TAG)

api-deploy:
	docker buildx build --platform linux/amd64 -t $(API_IMAGE):$(API_TAG) --push $(API_DIR)
	cd terraform && terraform workspace select prd && terraform apply -var-file="env/prd.tfvars" -var="api_image=$(API_IMAGE):$(API_TAG)"

api-run:
	cd $(API_DIR) && go run main.go

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
