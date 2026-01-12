# Terraform Workspaces

This configuration uses Terraform workspaces for multiple environments.

## Setup

```bash
cd terraform

# Initialize
terraform init

# Create workspaces
terraform workspace new dev
terraform workspace new prd
```

## Usage

### Development
```bash
terraform workspace select dev
terraform plan -var-file="env/dev.tfvars"
terraform apply -var-file="env/dev.tfvars"
```

### Production
```bash
terraform workspace select prd
terraform plan -var-file="env/prd.tfvars"
terraform apply -var-file="env/prd.tfvars"
```

## Environment Differences

| Config | dev | prd |
|--------|-----|-----|
| Min Instances | 0 | 1 |
| Max Instances | 5 | 20 |
| CPU | 1 | 2 |
| Memory | 512Mi | 1Gi |
| Deletion Protection | false | true |

## File Structure
```
terraform/
├── main.tf          # Provider + workspace locals
├── variables.tf     # Input variables
├── firestore.tf     # Firestore database
├── cloudrun.tf      # Cloud Run + Scheduler
├── identity.tf      # Identity Platform
├── outputs.tf       # Output values
└── env/
    ├── dev.tfvars   # Dev config
    └── prd.tfvars   # Prd config
```
