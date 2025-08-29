#!/usr/bin/env bash
set -euo pipefail

echo "[*] Updating apt..."
sudo apt-get update -y

# Make
sudo apt-get install -y make

# Google Cloud CLI
echo "[*] Installing Google Cloud CLI..."
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update -y
sudo apt-get install -y google-cloud-cli

# Terraform
echo "[*] Installing Terraform..."
sudo apt-get install -y gnupg software-properties-common wget
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
gpg --no-default-keyring \
  --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  --fingerprint
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update -y
sudo apt-get install -y terraform

# kubectl
echo "[*] Installing kubectl..."
sudo apt-get install -y kubectl

# Helm
echo "[*] Installing Helm..."
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Flux
echo "[*] Installing FluxCD CLI..."
curl -s https://fluxcd.io/install.sh | sudo bash

# k6
echo "[*] Installing k6..."
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 || true
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update -y
sudo apt-get install -y k6

echo "[*] All tools installed successfully!"
