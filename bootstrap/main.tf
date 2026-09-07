resource "google_storage_bucket" "state" {
  name                        = var.bucket_name
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  versioning { enabled = true }
  soft_delete_policy { retention_duration_seconds = 604800 }
  # Object retention locks would prevent Terraform from releasing its lock file.
  lifecycle_rule {
    condition {
      with_state                 = "ARCHIVED"
      num_newer_versions         = 20
      days_since_noncurrent_time = 90
    }
    action { type = "Delete" }
  }
  lifecycle { prevent_destroy = true }
}

resource "google_storage_bucket_iam_member" "state" {
  for_each = var.state_admin_members
  bucket   = google_storage_bucket.state.name
  role     = "roles/storage.objectAdmin"
  member   = each.value
}

