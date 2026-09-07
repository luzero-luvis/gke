output "name" {
  description = "Cluster name after GKE provisioning completes."
  value       = module.gke.name
}
output "dns_endpoint" {
  description = "IAM-protected DNS endpoint."
  value       = module.gke.endpoint_dns
}
