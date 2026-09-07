output "node_service_account" {
  description = "Dedicated node identity."
  value       = google_service_account.nodes.email
}
output "secrets_key_id" {
  description = "KMS key for Kubernetes Secrets."
  value       = google_kms_crypto_key.secrets.id
}
output "repository_id" {
  description = "Artifact Registry repository for application images."
  value       = google_artifact_registry_repository.apps.repository_id
}
