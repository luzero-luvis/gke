locals {
  public_apps = var.public_app == null ? {} : { app = var.public_app }
}

resource "google_compute_global_address" "app" {
  for_each = local.public_apps
  name     = "${var.cluster_name}-https"
}

data "google_dns_managed_zone" "public" {
  for_each = local.public_apps
  name     = each.value.dns_managed_zone
}

resource "google_dns_record_set" "app" {
  for_each     = local.public_apps
  managed_zone = data.google_dns_managed_zone.public[each.key].name
  name         = "${each.value.hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.app[each.key].address]
  lifecycle {
    precondition {
      condition = data.google_dns_managed_zone.public[each.key].visibility == "public" && (
        "${each.value.hostname}." == data.google_dns_managed_zone.public[each.key].dns_name ||
        endswith("${each.value.hostname}.", ".${data.google_dns_managed_zone.public[each.key].dns_name}")
      )
      error_message = "The hostname must belong to the selected public Cloud DNS zone."
    }
  }
}

resource "google_certificate_manager_dns_authorization" "app" {
  for_each = local.public_apps
  name     = "${var.cluster_name}-https"
  domain   = each.value.hostname
  type     = "PER_PROJECT_RECORD"
}

resource "google_dns_record_set" "certificate" {
  for_each     = local.public_apps
  managed_zone = data.google_dns_managed_zone.public[each.key].name
  name         = google_certificate_manager_dns_authorization.app[each.key].dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.app[each.key].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.app[each.key].dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "app" {
  for_each = local.public_apps
  name     = "${var.cluster_name}-https"
  managed {
    domains            = [each.value.hostname]
    dns_authorizations = [google_certificate_manager_dns_authorization.app[each.key].id]
  }
  depends_on = [google_dns_record_set.certificate]
}

resource "google_certificate_manager_certificate_map" "app" {
  for_each = local.public_apps
  name     = "${var.cluster_name}-https"
}

resource "google_certificate_manager_certificate_map_entry" "app" {
  for_each     = local.public_apps
  name         = "${var.cluster_name}-https"
  map          = google_certificate_manager_certificate_map.app[each.key].name
  hostname     = each.value.hostname
  certificates = [google_certificate_manager_certificate.app[each.key].id]
}

resource "google_compute_ssl_policy" "app" {
  for_each        = local.public_apps
  name            = "${var.cluster_name}-tls"
  min_tls_version = "TLS_1_2"
  profile         = "MODERN"
}

resource "google_compute_security_policy" "app" {
  for_each = local.public_apps
  name     = "${var.cluster_name}-armor"
  type     = "CLOUD_ARMOR"

  rule {
    priority    = 1000
    action      = "deny(403)"
    description = "SQL injection and XSS; observe legitimate traffic before enabling enforcement."
    preview     = each.value.waf_preview
    match {
      expr { expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1}) || evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})" }
    }
  }
  rule {
    priority = 2000
    action   = "throttle"
    match {
      versioned_expr = "SRC_IPS_V1"
      config { src_ip_ranges = ["*"] }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = each.value.requests_per_minute_per_ip
        interval_sec = 60
      }
    }
  }
  rule {
    priority = 2147483647
    action   = "allow"
    match {
      versioned_expr = "SRC_IPS_V1"
      config { src_ip_ranges = ["*"] }
    }
  }
}
