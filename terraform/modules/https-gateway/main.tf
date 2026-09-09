locals {
  # One shared IP/SSL policy/cert map regardless of how many apps share the Gateway.
  shared = length(var.public_apps) > 0 ? { app = true } : {}
  # Preserve the original unsuffixed names for the "app" key so an existing
  # single-app deployment doesn't force-replace its already-issued
  # certificate/policy when this module gains multi-app support. New app
  # keys get suffixed names to stay unique alongside it.
  https_name = { for k, v in var.public_apps : k => k == "app" ? "${var.cluster_name}-https" : "${var.cluster_name}-${k}-https" }
  armor_name = { for k, v in var.public_apps : k => k == "app" ? "${var.cluster_name}-armor" : "${var.cluster_name}-${k}-armor" }
}

resource "google_compute_global_address" "app" {
  for_each = local.shared
  name     = "${var.cluster_name}-https"
}

resource "google_compute_ssl_policy" "app" {
  for_each        = local.shared
  name            = "${var.cluster_name}-tls"
  min_tls_version = "TLS_1_2"
  profile         = "MODERN"
}

resource "google_certificate_manager_certificate_map" "app" {
  for_each = local.shared
  name     = "${var.cluster_name}-https"
}

data "google_dns_managed_zone" "public" {
  for_each = var.public_apps
  name     = each.value.dns_managed_zone
}

resource "google_dns_record_set" "app" {
  for_each     = var.public_apps
  managed_zone = data.google_dns_managed_zone.public[each.key].name
  name         = "${each.value.hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.app["app"].address]
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
  for_each = var.public_apps
  name     = local.https_name[each.key]
  domain   = each.value.hostname
  type     = "PER_PROJECT_RECORD"
}

resource "google_dns_record_set" "certificate" {
  for_each     = var.public_apps
  managed_zone = data.google_dns_managed_zone.public[each.key].name
  name         = google_certificate_manager_dns_authorization.app[each.key].dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.app[each.key].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.app[each.key].dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "app" {
  for_each = var.public_apps
  name     = local.https_name[each.key]
  managed {
    domains            = [each.value.hostname]
    dns_authorizations = [google_certificate_manager_dns_authorization.app[each.key].id]
  }
  depends_on = [google_dns_record_set.certificate]
}

resource "google_certificate_manager_certificate_map_entry" "app" {
  for_each     = var.public_apps
  name         = local.https_name[each.key]
  map          = google_certificate_manager_certificate_map.app["app"].name
  hostname     = each.value.hostname
  certificates = [google_certificate_manager_certificate.app[each.key].id]
}

resource "google_compute_security_policy" "app" {
  for_each = var.public_apps
  name     = local.armor_name[each.key]
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
