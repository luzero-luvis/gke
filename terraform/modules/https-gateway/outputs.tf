output "workload_config" {
  description = "References for the separately deployed Kubernetes Gateway resources: one shared Gateway plus one HTTPRoute/BackendPolicy per app."
  value = length(var.public_apps) == 0 ? null : {
    address_name    = google_compute_global_address.app["app"].name
    certificate_map = google_certificate_manager_certificate_map.app["app"].name
    ssl_policy      = google_compute_ssl_policy.app["app"].name
    apps = {
      for k, v in var.public_apps : k => {
        hostname        = v.hostname
        security_policy = google_compute_security_policy.app[k].name
      }
    }
  }
}
