output "network_name" {
  description = "VPC name."
  value       = google_compute_network.gke.name
}
output "subnetwork_name" {
  description = "Regional node subnet name."
  value       = google_compute_subnetwork.gke.name
}
output "ip_plan" {
  description = "Non-overlapping subnet allocation."
  value = {
    allocation = var.network_cidr
    nodes      = local.nodes_cidr
    pods       = local.pods_cidr
    services   = local.services_cidr
  }
}
