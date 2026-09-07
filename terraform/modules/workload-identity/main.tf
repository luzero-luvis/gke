resource "google_secret_manager_secret_iam_member" "workload" {
  for_each  = var.secret_access
  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/${each.value.namespace}/sa/${each.value.service_account}"
}

