output "bucket_name" {
  description = "Use as bucket in the infrastructure backend configuration."
  value       = google_storage_bucket.state.name
}
