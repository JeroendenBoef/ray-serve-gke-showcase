# ray-serve-gke-showcase
A repository showcasing a k8s deployment for Ray using Terraform on GKE

## Requirements
In order to fully manage the infrastructure, required packages are:
- gcloud
- terraform
- kubectl
- helm
- flux
- k6

## Initial setup
Install all required packages, login to gcp CLI, create a gcloud project, add billing to the project. Then enable the following APIs:
```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  artifactregistry.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com
```
Create a storage bucket in the same project using `gcloud storage buckets create gs` and enable versioning

## Terraform
Interact with terraform through make for simplicity:

```bash
make init       # terraform init
make plan       # terraform plan
make infra      # terraform apply -auto-approve
make creds      # fetch kubeconfig
make destroy    # terraform destroy -auto-approve
```