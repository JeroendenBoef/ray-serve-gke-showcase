# ray-serve-gke-showcase
A repository showcasing a k8s deployment for Ray using Terraform on GKE

## Requirements
In order to fully manage the infrastructure, required packages are:
- gcloud
- google-cloud-cli-gke-gcloud-auth-plugin
- terraform
- kubectl
- helm
- flux
- k6
- SOPS
- age

This repository uses flux for GitOps. Write access to the repository is required for flux to function, so the repository must be forked if you intend to run this infrastructure yourself.

## Initial setup
Fork the repository and install all required packages with `./scripts/install_admin_tools.sh`. After installing all prerequisite packages, login to gcp CLI, create a gcloud project, add billing to the project. Create a storage bucket in the same project using `gcloud storage buckets create gs` and enable versioning. 

Create a .env file from the .env.example template with `cp .env.example .env` and populate it with the project id of your GCP project, your preferred region, zone, a cluster name, your gcloud storage bucket and your github owner/org, forked repo and branch to bootstrap to. This .env file is used by the Makefile and terraform to fetch variables that are required to determine factors like the project ID, compute regions, bootstrapping branch, etc.

A Makefile is provided to streamline CLI commands. The following commands are supported:
```bash
make init           # terraform init
make plan           # terraform plan
make plan-save      # terraform plan -out=tfplan
make apply-plan     # terraform apply tfplan
make infra          # terraform apply -auto-approve
make creds          # fetch kubeconfig
make destroy        # terraform destroy -auto-approve
make flux-wi        # bind flux encryption key
make flux-bootstrap # flux bootstrap
```
After all requirements are installed, a gcloud project has been created, billing has been attached, a storage bucket has been created and the .env file has been populated, create the cluster with:

```bash
make init
make plan-save
make apply-plan
```

Verify the cluster status through GCP CLI with `gcloud container clusters list --project $PROJECT_ID --region $REGION`. If the cluster is healthy and running, generate a local kubeconfig with `make creds`. The cluster will now accept normal kubectl commands.