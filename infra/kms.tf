resource "google_service_account" "flux_sops" {
  account_id   = "flux-sops-sa"
  display_name = "Flux SOPS Decrypter"
  project      = var.project_id
}

resource "google_kms_crypto_key_iam_binding" "sops_decrypter" {
  crypto_key_id = format(
    "projects/%s/locations/%s/keyRings/%s/cryptoKeys/%s",
    var.project_id, var.region, var.kms_key_ring, var.kms_crypto_key
  )
  role    = "roles/cloudkms.cryptoKeyDecrypter"
  members = ["serviceAccount:${google_service_account.flux_sops.email}"]
}

output "flux_sops_gsa_email" {
  value       = google_service_account.flux_sops.email
  description = "GCP service account for Flux decryption"
}
