output "secret_principals" {
  description = "Kubernetes identities granted access to individual secrets."
  value       = { for k, grant in google_secret_manager_secret_iam_member.workload : k => grant.member }
}
