resource "google_kms_key_ring" "flux" {
  name     = "flux-sops-tf"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "sops" {
  name            = "sops-key-tf"
  key_ring        = google_kms_key_ring.flux.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "2592000s"
}

resource "google_service_account" "flux_sops" {
  account_id   = "flux-sops-sa"
  display_name = "Flux SOPS Decrypter"
  project      = var.project_id
}

resource "google_kms_crypto_key_iam_binding" "sops_decrypter" {
  crypto_key_id = google_kms_crypto_key.sops.id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  members = [
    "serviceAccount:${google_service_account.flux_sops.email}",
  ]
}

output "flux_sops_gsa_email" {
  value       = google_service_account.flux_sops.email
  description = "GCP service account for Flux decryption"
}

output "sops_kms_resource" {
  value       = google_kms_crypto_key.sops.id
  description = "Full resource ID of the KMS key for SOPS"
}
