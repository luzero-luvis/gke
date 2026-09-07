mock_provider "google" {
  mock_data "google_project" {
    defaults = { number = "123456789012" }
  }
  mock_data "google_dns_managed_zone" {
    defaults = { name = "example-com", dns_name = "example.com.", visibility = "public" }
  }
}
mock_provider "google-beta" {}
mock_provider "kubernetes" {}
mock_provider "random" {}

variables {
  project_id    = "gke-foundation-test"
  cluster_name  = "production-gke"
  region        = "asia-south1"
  zones         = ["asia-south1-a", "asia-south1-b", "asia-south1-c"]
  backup_region = "asia-south2"
}

run "private_foundation" {
  command = plan
  assert {
    condition     = output.ip_plan.nodes == "10.64.0.0/20" && output.ip_plan.pods == "10.65.0.0/16" && output.ip_plan.services == "10.66.0.0/20"
    error_message = "Node, Pod, and Service allocations must remain separate."
  }
  assert {
    condition     = output.ip_plan.max_nodes + output.ip_plan.surge_nodes <= output.ip_plan.pod_range_node_capacity
    error_message = "Autoscaling and upgrades must fit within the Pod allocation."
  }
  assert {
    condition     = output.workload_config.public_app == null && !output.release_readiness.attestation_enforced && !output.release_readiness.alert_delivery_configured
    error_message = "Unset deployment choices must be reported honestly."
  }
}

run "public_foundation" {
  command = plan
  variables {
    public_app                     = { hostname = "api.example.com", dns_managed_zone = "example-com", waf_preview = false }
    binary_authorization_attestors = ["projects/gke-foundation-test/attestors/release"]
    notification_channels          = ["projects/gke-foundation-test/notificationChannels/123"]
    secret_access = {
      app = { secret_id = "app-password", namespace = "apps", service_account = "app" }
    }
  }
  assert {
    condition     = output.workload_config.public_app.hostname == "api.example.com" && output.release_readiness.waf_enforced && output.release_readiness.attestation_enforced
    error_message = "Configured HTTPS and release enforcement must reach the deployment outputs."
  }
}

run "reject_overlapping_environment_allocation" {
  command = plan
  variables { network_cidr = "10.65.0.0/14" }
  expect_failures = [var.network_cidr]
}

run "reject_single_region_backup" {
  command = plan
  variables { backup_region = "asia-south1" }
  expect_failures = [var.backup_region]
}

run "reject_duplicate_zones" {
  command = plan
  variables { zones = ["asia-south1-a", "asia-south1-a", "asia-south1-c"] }
  expect_failures = [var.zones]
}

run "reject_pod_ip_exhaustion" {
  command = plan
  variables { max_nodes_per_zone = 171 }
  expect_failures = [var.max_nodes_per_zone]
}
