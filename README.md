# ray-serve-gke-showcase

This repository demonstrates how to provision a Google Kubernetes Engine (GKE) cluster using Terraform, deploy a Ray Serve application via Flux (GitOps), and run smoke/perf tests using k6. The Ray Serve app exposes an /infer endpoint for a simple sentiment analysis pipeline that is capable of running on GPUs.

### Key Features

- **Infrastructure as Code (IaC)** with Terraform: Creates a GKE cluster with CPU and GPU node pools, and provisions a KMS key for SOPS encryption.
- **GitOps** with Flux: Manages Kubernetes resources declaratively, including Ingress NGINX, KubeRay operator, and the workload deployments.
- **Ray Serve application**: A three-stage pipeline (preprocess → inference → postprocess) with dynamic batching and autoscaling; inference can run on GPUs when available.
- **Monitoring stack**: Uses the kube-prometheus-stack Helm chart to install Prometheus and Grafana. Grafana credentials are encrypted with SOPS.
- **Smoke/perf tests**: Provides k6 scripts to test both external (via Ingress) and internal (in-cluster) request latencies.
- **Bootstrap scripts and Makefile**: A helper script installs required CLI tools, and a comprehensive Makefile wraps Terraform, Flux, and SOPS commands.

## Contents

- [Requirements](#requirements)
- [Prerequisites](#prerequisites)
- [Initial setup](#initial-setup)
- [Flux bootstrap & GitOps](#flux-bootstrap--gitops)
- [Ray Serve application](#ray-serve-application)
- [Smoke/perf testing](#smoke-tests)
- [Accessing monitoring dashboard](#accessing-monitoring-dashboards)
- [Cleaning up](#cleaning-up)

## Requirements

To fully use this repository, you need the following tools installed locally:

- `gcloud` & `google-cloud-cli-gke-gcloud-auth-plugin`
- `terraform` (>= 1.5.0)
- `kubectl`
- `helm`
- `flux`
- `k6`
- `sops`

These required packages can be install with `./scripts/install_admin_tools.sh`. A fork of this repository (write access required) is needed for Flux.

## Prerequisites

1. Create a GCP project and enable billing.
2. Required APIs
    - Enable the following APIs in your project:
      - `container.googleapis.com`
      - `compute.googleapis.com`
      - `iam.googleapis.com`
      - `cloudkms.googleapis.com`
      - `serviceusage.googleapis.com`
      - `artifactregistry.googleapis.com`
      - `monitoring.googleapis.com`
      - `logging.googleapis.com`
3. Create a GCS bucket for Terraform state and enable versioning:

```bash
gsutil mb -l <REGION> gs://<your-tf-state-bucket>
gsutil versioning set on gs://<your-tf-state-bucket>
```

4. Fork this repo to your GitHub account/org and clone the fork locally.
5. Docker registry access
    - The Ray Serve application runs in a custom container image. Either use the provided image (e.g. jeroendenboef/jdb-personal-dev:ray-serve-2.9.0-app.7) or build/push your own image (see Building the Ray Serve image
    ). You need access to a Docker registry.
6. Fill out environment variables
    - Copy the example .env and update it with your values:

```bash
cp .env.example .env
# Edit .env and set:
#   PROJECT_ID=<your-project-id>
#   REGION=<e.g. europe-west4>
#   ZONE=<e.g. europe-west4-b>
#   CLUSTER=<desired-cluster-name>
#   TF_BACKEND_BUCKET=<your-tf-state-bucket>
#   KMS_KEY_RING=<name-of-your-kms-key-ring>
#   KMS_CRYPTO_KEY=<kms-key-name>
#   GITHUB_OWNER=<your-github-username-or-org>
#   GITHUB_REPO=<your-forked-repo-name>
#   GITHUB_BRANCH=<branch Flux should monitor
```
7. Export your .env file to your shell for ease of use.

### Building the Ray Serve Image

The provided Ray Serve application is packaged in a Docker image. A reference Dockerfile is provided in `Dockerfiles/ray-serve.Dockerfile` To build your own image:

1. Build and push the image

```bash
docker build -t <registry>/<repository>:<tag> -f Dockerfiles/ray-serve.Dockerfile .
docker push <registry>/<repository>:<tag>
```

2. Update the image fields in apps/ray/rayservice.yaml to point to your new image.

## Initial setup

1. Provision the KMS key (only needed once)

Terraform in the `infra-bootstrap/` directory creates a KMS keyring and key used by SOPS:

```bash
# Initialize and apply infra-bootstrap
make bootstrap-init
make bootstrap-plan
make bootstrap-apply
```

2. Provision the GKE cluster

The infra/ module uses the Kubernetes Engine Terraform module to create a GKE cluster with CPU and GPU node pools:

```bash
make init
make plan-save
make apply-plan
# Verify the cluster
gcloud container clusters list --project $PROJECT_ID --region $REGION
```

Warning: The default node pools are pre-emptible; pods on them may be evicted. Increase node pool min replicas or use non-pre-emptible nodes for production workloads.

3. Get cluster credentials:

```bash
make creds
kubectl get nodes -o wide
```

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
    - flux-wait (waits until kustomizations are applied)
    - flux-reconcile (forces a refresh)

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

## Accessing Monitoring Dashboards

The kube-prometheus-stack includes Grafana and Prometheus. Default admin user/password is stored in the grafana-admin secret. Delete the existing grafana-admin.yaml,c reate your own encrypted `apps/monitoring/secrets/grafana-admin.yaml` from the template `grafana-admin-template.yaml` in the same folder, encrypt with `make sops-encrypt FILE=apps/monitoring/secrets/grafana-admin.yaml`, push to git and reconcile flux. To view dashboards:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# Then open http://localhost:3000 in your browser
```

Use your credentials stored in your newly encrypted `apps/monitoring/secrets/grafana-admin.yaml`. Once logged in, import Ray dashboards or create your own. To scrape Ray metrics automatically, set the following values in `apps/kuberay/helmrelease.yaml`:

```yaml
values:
  metrics:
    serviceMonitor:
      enabled: true
      selector:
        release: prometheus
```

After applying those changes via Flux, Prometheus will start scraping the Ray metrics endpoint and Grafana will show Ray Serve dashboards.

## Cleaning Up

To tear down the GKE cluster, run `make destroy`. If you want to destroy the KMS key, you may need to disable its `lifecycle.prevent_destroy` first. To destroy it: `cd infra-bootstrap && terraform destroy`. Destroying the KMS key makes it impossible to decrypt any remaining encrypted secrets.
