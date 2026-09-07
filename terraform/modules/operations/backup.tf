resource "google_gke_backup_backup_plan" "apps" {
  name     = "${var.cluster_name}-apps"
  location = var.backup_region
  cluster  = "projects/${var.project_id}/locations/${var.region}/clusters/${var.cluster_name}"
  labels   = var.labels
  backup_config {
    include_volume_data = true
    include_secrets     = true
    selected_namespaces { namespaces = var.backup_namespaces }
  }
  backup_schedule { cron_schedule = "0 */6 * * *" }
  retention_policy {
    backup_retain_days      = 30
    backup_delete_lock_days = 7
  }
  lifecycle { prevent_destroy = true }
}
