-include .env
export $(shell sed 's/=.*//' .env 2>/dev/null)

export TF_VAR_project_id=$(PROJECT_ID)
export TF_VAR_region=$(REGION)
export TF_VAR_zone=$(ZONE)
export TF_VAR_kms_key_ring=$(KMS_KEY_RING)
export TF_VAR_kms_crypto_key=$(KMS_CRYPTO_KEY)

.PHONY: bootstrap-init bootstrap-plan bootstrap-apply init plan plan-save apply-plan infra creds destroy  flux-wi flux-bootstrap sops-init sops-encrypt sops-edit sops-verify

bootstrap-init:
	cd infra-bootstrap && terraform init \
	  -backend-config="bucket=$(TF_BACKEND_BUCKET)" \
	  -backend-config="prefix=$(TF_BOOTSTRAP_BACKEND_PREFIX)"

bootstrap-plan:
	cd infra-bootstrap && terraform plan

bootstrap-apply:
	cd infra-bootstrap && terraform apply -auto-approve

init:
	cd infra && terraform init \
    -backend-config="bucket=$(TF_BACKEND_BUCKET)" \
    -backend-config="prefix=$(TF_BACKEND_PREFIX)"

plan:
	cd infra && terraform plan

plan-save:
	cd infra && terraform plan -out=tfplan

apply-plan:
	cd infra && terraform apply tfplan

infra:
	cd infra && terraform apply -auto-approve

creds:
	gcloud container clusters get-credentials $(CLUSTER) --region $(REGION) --project $(PROJECT_ID)

destroy:
	cd infra && terraform destroy -auto-approve

# Bind Flux's kustomize-controller KSA to the GSA from Terraform output
flux-wi:
	@GSA_EMAIL=$$(cd infra && terraform output -raw flux_sops_gsa_email); \
	kubectl -n flux-system annotate serviceaccount kustomize-controller \
	  iam.gke.io/gcp-service-account=$$GSA_EMAIL --overwrite

flux-bootstrap:
	flux bootstrap github \
	  --owner $${GH_OWNER:?set GH_OWNER in .env} \
	  --repository $${GH_REPO:?set GH_REPO in .env} \
	  --branch $${GH_BRANCH:-main} \
	  --path clusters/prod

# Generate .sops.yaml from .env and .sops.yaml.tmpl
sops-init:
	@[ -f .env ] || (echo "Missing .env; copy .env.example -> .env and fill in"; exit 1)
	envsubst < .sops.yaml.tmpl > .sops.yaml
	@echo "Rendered .sops.yaml from template."

# Encrypt a file with sops (usage: make sops-encrypt FILE=apps/monitoring/secrets/grafana-admin.yaml)
sops-encrypt:
	@[ -n "$$FILE" ] || (echo "Usage: make sops-encrypt FILE=path/to/secret.yaml"; exit 1)
	sops --encrypt --in-place $$FILE
	@echo "Encrypted $$FILE"

# Verify communication of current creds <> KMS
sops-verify:
	@gcloud auth application-default print-access-token >/dev/null || (echo "Run: gcloud auth application-default login"; exit 1)
	@echo "ADC OK. Ensure your user has roles/cloudkms.cryptoKeyEncrypterDecrypter on the key."