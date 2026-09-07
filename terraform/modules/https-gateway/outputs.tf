output "workload_config" {
  description = "References for the separately deployed Kubernetes Gateway resources."
  value = var.public_app == null ? null : {
    hostname        = var.public_app.hostname
    address_name    = google_compute_global_address.app["app"].name
    certificate_map = google_certificate_manager_certificate_map.app["app"].name
    security_policy = google_compute_security_policy.app["app"].name
    ssl_policy      = google_compute_ssl_policy.app["app"].name
  }
}
