resource "google_kms_key_ring" "flux" {
  name     = var.kms_key_ring
  location = var.region
  project  = var.project_id

  lifecycle { prevent_destroy = true }
}

resource "google_kms_crypto_key" "sops" {
  name            = var.kms_crypto_key
  key_ring        = google_kms_key_ring.flux.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "2592000s"

  lifecycle { prevent_destroy = true }
}

output "kms_crypto_key_id" {
  value       = google_kms_crypto_key.sops.id
  description = "Full resource ID of the KMS key"
}
