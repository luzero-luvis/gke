output "cluster_name" {
  description = "Regional GKE cluster name."
  value       = module.gke_cluster.name
}

output "get_credentials_command" {
  description = "Run with an authorized identity and the GKE gcloud auth plugin installed."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --project=${var.project_id} --region=${var.region} --dns-endpoint"
}

output "ip_plan" {
  description = "Address allocation and capacity including upgrade surge."
  value = merge(module.network.ip_plan, {
    pod_cidr_per_node       = "/25"
    pod_range_node_capacity = 512
    min_nodes               = 3
    max_nodes               = var.max_nodes_per_zone * 3
    surge_nodes             = 3
  })
}

output "workload_config" {
  description = "Non-secret configuration consumed by scripts/render-workloads.py."
  value = {
    project_id   = var.project_id
    region       = var.region
    cluster_name = module.gke_cluster.name
    repository   = "${var.region}-docker.pkg.dev/${var.project_id}/${module.security.repository_id}"
    public_app   = module.https_gateway.workload_config
  }
}

output "backup_plan" {
  description = "Backup plan resource; a successful restore drill is still required."
  value       = module.operations.backup_plan
}

output "release_readiness" {
  description = "Environment choices that must be resolved before serving production traffic."
  value = {
    alert_delivery_configured = length(var.notification_channels) > 0
    attestation_enforced      = length(var.binary_authorization_attestors) > 0
    public_https_configured   = var.public_app != null
    waf_enforced              = var.public_app == null ? false : !var.public_app.waf_preview
    requires_restore_drill    = true
    requires_load_test        = true
  }
}
