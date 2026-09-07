locals {
  nodes_cidr    = cidrsubnet(var.network_cidr, 6, 0)
  pods_cidr     = cidrsubnet(var.network_cidr, 2, 1)
  services_cidr = cidrsubnet(var.network_cidr, 6, 32)
}

resource "google_compute_network" "gke" {
  name                            = "${var.cluster_name}-vpc"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "gke" {
  name                     = "${var.cluster_name}-nodes"
  region                   = var.region
  network                  = google_compute_network.gke.id
  ip_cidr_range            = local.nodes_cidr
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = local.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = local.services_cidr
  }
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.1
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "gke" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.gke.id
}

resource "google_compute_router_nat" "gke" {
  name                                = "${var.cluster_name}-nat"
  router                              = google_compute_router.gke.name
  region                              = var.region
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "LIST_OF_SUBNETWORKS"
  enable_dynamic_port_allocation      = true
  enable_endpoint_independent_mapping = false
  min_ports_per_vm                    = 64
  max_ports_per_vm                    = 4096
  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Google API VIPs allow a narrow HTTPS egress exception in NetworkPolicy.
# This is connectivity, not a VPC Service Controls perimeter.
resource "google_dns_managed_zone" "googleapis" {
  name       = "${var.cluster_name}-googleapis"
  dns_name   = "googleapis.com."
  visibility = "private"
  private_visibility_config {
    networks { network_url = google_compute_network.gke.id }
  }
}

resource "google_dns_record_set" "private_googleapis" {
  managed_zone = google_dns_managed_zone.googleapis.name
  name         = "private.googleapis.com."
  type         = "A"
  ttl          = 300
  rrdatas      = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
}

resource "google_dns_record_set" "googleapis" {
  managed_zone = google_dns_managed_zone.googleapis.name
  name         = "*.googleapis.com."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [google_dns_record_set.private_googleapis.name]
}
