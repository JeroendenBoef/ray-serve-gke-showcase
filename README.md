# ray-serve-gke-showcase
A reproducible GKE deployment for Ray Serve using Terraform + Flux (GitOps), with optional GPU workers and a k6 smoke/perf test.

## Contents
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Prerequisites](#prerequisites)
- [Initial setup](#initial-setup)
- [Flux bootstrap & GitOps](#flux-bootstrap--gitops)
- [Ray Serve application](#ray-serve-application)
- [Smoke/perf testing](#smoke-tests)

## Architecture
- Terraform:
  - Creates a GKE cluster with CPU and GPU node pools (T4). The Ray Serve app is compatible with full CPU deployment as well.
  - Installs Ingress-NGINX (public LB), metrics stack, and cluster add-ons.
- Flux (GitOps):
  - Applies manifests under clusters/prod.
  - Manages platform components and workloads.
- KubeRay operator manages RayService (blue/green rollout via active/pending RayClusters).
- Ray Serve
  - Exposes /infer for a simple sentiment classification pipeline using DistilBERT.
  - Inference can run on GPU (when quota allows) with dynamic batching and autoscaling.

#### GPU quotas
If you plan to use a GPU worker, set Global T4 quota and Regional T4 quota to at least 1. For smooth blue/green upgrades, 2 is recommended.

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

These required packages can be install with `./scripts/install_admin_tools.sh`. A fork of this repository (write access required) is needed for Flux. 

## Prerequisites
1. Create a GCP project and enable billing.
2. Enable APIs you’ll need (GKE, Compute, Container Registry/Artifact Registry, etc.).
3. Create a GCS bucket for Terraform state and enable versioning:
```bash
gcloud storage buckets create gs://<your-tf-state-bucket> --location=<REGION>
gcloud storage buckets update gs://<your-tf-state-bucket> --versioning
```
4. Fork this repo to your GitHub account/org.

## Initial setup
1. Clone your fork and create a local .env from the template with `cp .env.example .env`. Within the `.env` file, populate:
    - `PROJECT_ID`: your GCP project ID
    - `REGION`: e.g. europe-west4
    - `ZONE`: e.g. europe-west4-b
    - `CLUSTER`: e.g. ray-serve-gke
    - `TF_BACKEND_BUCKET`: your GCS bucket for TF state
    - `KMS_KEY_RING`, `KMS_CRYPTO_KEY`: keyring and key names, will be created on first run or reused if already existing
    - `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_BRANCH`: your fork details and branch for flux to monitor

2. Terraform up with Makefile aliases:
```bash
# Generate KMS keyring and key prior on first terraform apply, skip this step after
make bootstrap-init
make bootstrap-plan
make bootstrap-apply

make init
make plan-save
make apply-plan
```
Verify resulting infra with `gcloud container clusters list --project $PROJECT_ID --region $REGION`

3. Get kubeconfig:
```bash
make creds    # sets kube context to the new cluster
kubectl get nodes -o wide
```

The majority of the infra can be brought down with `make terraform-destroy`.

## Flux bootstrap & GitOps
This repository uses Flux for GitOps. The flux-system manifests are committed to this repo and can be reused, or flux can be bootstrapped from scratch if the flux-bootstrap dir is removed. For a clean bootstrap in a fork that does not contain `clusters/prod/flux-system`:

1. Generate a GitHub PAT (scope: `repo`) for Flux to push/commit if needed.
2. Bootstrap Flux:
```bash
make flux-bootstrap
make flux-vars
make flux-reconcile
```
### When to use flux-up (rehydration)

Use this on a repo that already contains clusters/prod/flux-system (e.g., you forked this repo and don't want to change the directory tree):
1. Generate an SSH deploy key for Flux (only once per machine) with: `make flux-keygen`. Add the printed public key as a read-only Deploy Key in your GitHub repo settings.
2. Rehydrate Flux from the committed manifests with: `make flux-up` This will run:
    - flux-git-secret-ssh (creates flux-system secret with your SSH key + known_hosts)
    - flux-vars (creates a GSA_EMAIL secret used by kustomizations)
    - flux-apply (applies clusters/prod/flux-system)
    - flux-wait (waits until kustomizations are applied) ← see Makefile note below
    - lux-reconcile (forces a refresh)

### SOPS
Encryption is handled by SOPS + KMS, render from template with `make sops-init`. Verify with `make sops-verify`. Encrypt a secret with `make sops-encrypt FILE=path/to/yaml`.

## Ray Serve application
- Main manifest: `apps/ray/rayservice.yaml`.
- Uses KubeRay RayService with blue/green updates (active + pending clusters).
- Default app endpoint: `route_prefix: /infer`.
- Inference uses:
  - Dynamic batching (`@serve.batch`)
  - GPU (`num_gpus: 1`) when available
  - Warmup in `__init__`
  - CUDA AMP only when `cuda` is available (prevents CPU half-precision errors)

### Sending inference requests
This implementation exposes an endpoint publicly via Ingress-NGINX with a public load balancer IP, excluding authentication. Access should be restricted for production systems.

Send an inference request to `/infer`:

```bash
ING=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s -X POST "http://$ING/infer" -H "Content-Type: application/json" \
  -d '{"inputs":["I love this!", "This is awful."]}'
```

## Smoke tests
k6 load tests are provided for internal and external requests. External tests will evaluate real-world latency by routing via the ingress and LB. Internal tests isolate app performance without ingress overhead. Run external smoke tests (outside of cluster) with:

```bash
ING=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INFER_URL="http://$ING/infer"
k6 run --summary-export=results_external.json tests/smoke.js
```

Run internal smoke tests (within cluster) by applying the configmap and job:

```bash
kubectl -n ray apply -f k6/k6-config.yaml
kubectl -n ray apply -f k6/k6-job.yaml

# After pod terminates
POD=$(kubectl -n ray get pod -l job-name=k6-smoke \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
kubectl -n ray cp -c holder "$POD":/out/results_int.json ./k6/results_internal.json
```

Thresholds used in these tests are:

```js
thresholds: {
  http_req_failed: ['rate<0.01'],
  http_req_duration: ['p(95)<800'],
}
```

### Results & summary
Full results are in `k6/results_external.json` and `k6/results_internal.json`. Below are extracted and summarized results:

| Scenario | Target RPS | Effective RPS | p95 Latency | Avg Latency | Error Rate | Notes                                                                             |
| -------- | ---------: | ------------: | ----------: | ----------: | ---------: | --------------------------------------------------------------------------------- |
| External |   up to 60 |   **15.09/s** | **14.65 s** |      4.74 s | **16.79%** | Hit VU cap & backpressure; ingress + app bottleneck; many dropped iterations.     |
| Internal |    5→10→15 |    **7.66/s** |  **149 ms** |     67.8 ms |  **0.22%** | Healthy latencies; very low error rate; good app health without Internet/ingress. |

Internal (in-cluster) p95 latency is **~149 ms with 0.22%** errors at ~7.7 req/s.
External (through Ingress) p95 latency is **~14.7 s with 16.8%** errors when attempting to ramp to 60 req/s; effective throughput capped at ~15 req/s with many dropped iterations.
This indicates the Ray Serve app is healthy, and the bottleneck for high RPS is ingress+replica capacity and/or autoscaling limits. These tests were performed under the restriction of a global GPU quota of 1. For more insightful tests, global GPU quota should be raised so the `Inference` deployment can be autoscaled. Internal tests were also performed with higher RPS but they also bottlenecked at 15.