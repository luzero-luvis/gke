module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "44.3.0"

  project_id = var.project_id
  name       = var.cluster_name
  regional   = true
  region     = var.region
  zones      = var.zones

  network           = var.network_name
  subnetwork        = var.subnetwork_name
  ip_range_pods     = "pods"
  ip_range_services = "services"
  stack_type        = "IPV4"
  datapath_provider = "ADVANCED_DATAPATH"
  # Dataplane V2 enforces NetworkPolicy natively. Do not install Calico.
  network_policy = false

  enable_private_nodes                 = true
  enable_private_endpoint              = true
  master_global_access_enabled         = false
  ip_endpoints_enabled                 = false
  dns_allow_external_traffic           = true
  dns_enable_k8s_tokens_via_dns        = false
  issue_client_certificate             = false
  authenticator_security_group         = var.authenticator_security_group
  anonymous_authentication_config_mode = "LIMITED"
  rbac_binding_config = {
    enable_insecure_binding_system_unauthenticated = false
    enable_insecure_binding_system_authenticated   = false
  }

  cluster_dns_provider        = "CLOUD_DNS"
  cluster_dns_scope           = "CLUSTER_SCOPE"
  dns_cache                   = true
  identity_namespace          = "enabled"
  node_metadata               = "GKE_METADATA"
  enable_shielded_nodes       = true
  enable_secret_manager_addon = true
  enable_binary_authorization = true
  security_posture_mode       = "BASIC"
  # GKE workload vulnerability scanning has been retired; scan Artifact Registry.
  security_posture_vulnerability_mode = "VULNERABILITY_DISABLED"
  database_encryption                 = [{ state = "ENCRYPTED", key_name = var.secrets_key_id }]

  release_channel        = var.release_channel
  maintenance_start_time = var.maintenance_window.start_time
  maintenance_end_time   = var.maintenance_window.end_time
  maintenance_recurrence = var.maintenance_window.recurrence
  deletion_protection    = true

  remove_default_node_pool               = true
  initial_node_count                     = 1
  default_max_pods_per_node              = 64
  create_service_account                 = false
  service_account                        = var.node_service_account
  grant_registry_access                  = false
  disable_legacy_metadata_endpoints      = true
  insecure_kubelet_readonly_port_enabled = false

  node_pools = [{
    name                                   = "general"
    machine_type                           = var.machine_type
    node_locations                         = join(",", var.zones)
    min_count                              = 1
    max_count                              = var.max_nodes_per_zone
    initial_node_count                     = 1
    autoscaling                            = true
    location_policy                        = "BALANCED"
    auto_repair                            = true
    auto_upgrade                           = true
    image_type                             = "COS_CONTAINERD"
    disk_type                              = "pd-balanced"
    disk_size_gb                           = 100
    max_pods_per_node                      = 64
    spot                                   = false
    enable_private_nodes                   = true
    enable_secure_boot                     = true
    enable_integrity_monitoring            = true
    insecure_kubelet_readonly_port_enabled = false
    cpu_manager_policy                     = "none"
    strategy                               = "SURGE"
    max_surge                              = 1
    max_unavailable                        = 0
  }]
  node_pools_metadata        = { all = { "block-project-ssh-keys" = "true" } }
  node_pools_oauth_scopes    = { all = ["https://www.googleapis.com/auth/cloud-platform"] }
  node_pools_resource_labels = { all = var.labels }
  cluster_resource_labels    = var.labels

  horizontal_pod_autoscaling           = true
  enable_vertical_pod_autoscaling      = true
  http_load_balancing                  = true
  gateway_api_channel                  = "CHANNEL_STANDARD"
  service_external_ips                 = false
  gce_pd_csi_driver                    = true
  gke_backup_agent_config              = true
  enable_cost_allocation               = true
  monitoring_enable_managed_prometheus = true
  logging_enabled_components           = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  monitoring_enabled_components        = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "STORAGE", "HPA", "POD", "DEPLOYMENT", "STATEFULSET", "DAEMONSET"]

}
