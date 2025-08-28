PROJECT_ID ?= ray-serve-gke-showcase-1122
REGION     ?= europe-west4
CLUSTER    ?= ray-serve-gke

.PHONY: init plan infra creds destroy

init:
	cd infra && terraform init

plan:
	cd infra && terraform plan

infra:
	cd infra && terraform apply -auto-approve

creds:
	gcloud container clusters get-credentials $(CLUSTER) --region $(REGION) --project $(PROJECT_ID)

destroy:
	cd infra && terraform destroy -auto-approve
