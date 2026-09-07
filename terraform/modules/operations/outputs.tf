output "backup_plan" {
  description = "Backup for GKE plan resource name."
  value       = google_gke_backup_backup_plan.apps.id
}
