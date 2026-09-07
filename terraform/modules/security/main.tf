resource "google_service_account" "nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE node runtime only"
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.nodes.member
}

resource "google_project_iam_member" "cluster_access" {
  for_each = var.cluster_access_members
  project  = var.project_id
  role     = "roles/container.clusterViewer"
  member   = each.value
}

resource "google_kms_key_ring" "gke" {
  name     = "${var.cluster_name}-secrets"
  location = var.region
}

resource "google_kms_crypto_key" "secrets" {
  name            = "kubernetes-secrets"
  key_ring        = google_kms_key_ring.gke.id
  rotation_period = "7776000s"
  lifecycle { prevent_destroy = true }
}

resource "google_kms_crypto_key_iam_member" "gke" {
  crypto_key_id = google_kms_crypto_key.secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.gke_service_agent_email}"
}

resource "google_artifact_registry_repository" "apps" {
  location      = var.region
  repository_id = "${var.cluster_name}-apps"
  format        = "DOCKER"
  labels        = var.labels
  docker_config { immutable_tags = true }
  # Keep release history until the team's rollback retention is agreed.
  cleanup_policy_dry_run = true
  vulnerability_scanning_config { enablement_config = "INHERITED" }
  lifecycle { prevent_destroy = true }
}

resource "google_artifact_registry_repository_iam_member" "nodes" {
  location   = google_artifact_registry_repository.apps.location
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.nodes.member
}

resource "google_binary_authorization_policy" "project" {
  project                       = var.project_id
  global_policy_evaluation_mode = "ENABLE"
  default_admission_rule {
    evaluation_mode         = length(var.binary_authorization_attestors) > 0 ? "REQUIRE_ATTESTATION" : "ALWAYS_DENY"
    enforcement_mode        = length(var.binary_authorization_attestors) > 0 ? "ENFORCED_BLOCK_AND_AUDIT_LOG" : "DRYRUN_AUDIT_LOG_ONLY"
    require_attestations_by = var.binary_authorization_attestors
  }
}

# Authoritative per-service audit configuration: import/reconcile an existing
# project's audit configs before adopting this new-project foundation.
resource "google_project_iam_audit_config" "data_access" {
  for_each = toset(["container.googleapis.com", "secretmanager.googleapis.com", "cloudkms.googleapis.com", "artifactregistry.googleapis.com"])
  project  = var.project_id
  service  = each.value
  audit_log_config { log_type = "ADMIN_READ" }
  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
}
