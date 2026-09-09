resource "google_project_service" "required" {
  for_each           = local.services
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

resource "google_project_service_identity" "gke" {
  provider   = google-beta
  project    = var.project_id
  service    = "container.googleapis.com"
  depends_on = [google_project_service.required]
}

module "network" {
  source       = "./modules/network"
  cluster_name = var.cluster_name
  region       = var.region
  network_cidr = var.network_cidr
  depends_on   = [google_project_service.required]
}

module "security" {
  source                         = "./modules/security"
  project_id                     = var.project_id
  region                         = var.region
  cluster_name                   = var.cluster_name
  labels                         = local.labels
  gke_service_agent_email        = google_project_service_identity.gke.email
  cluster_access_members         = var.cluster_access_members
  binary_authorization_attestors = var.binary_authorization_attestors
  depends_on                     = [google_project_service.required]
}

module "gke_cluster" {
  source                       = "./modules/gke-cluster"
  project_id                   = var.project_id
  region                       = var.region
  zones                        = var.zones
  cluster_name                 = var.cluster_name
  network_name                 = module.network.network_name
  subnetwork_name              = module.network.subnetwork_name
  node_service_account         = module.security.node_service_account
  secrets_key_id               = module.security.secrets_key_id
  machine_type                 = var.machine_type
  max_nodes_per_zone           = var.max_nodes_per_zone
  release_channel              = var.release_channel
  maintenance_window           = var.maintenance_window
  authenticator_security_group = var.authenticator_security_group
  labels                       = local.labels
  depends_on                   = [module.network, module.security]
}

module "workload_identity" {
  source         = "./modules/workload-identity"
  project_id     = var.project_id
  project_number = data.google_project.current.number
  secret_access  = var.secret_access
  depends_on     = [module.gke_cluster]
}

module "https_gateway" {
  source       = "./modules/https-gateway"
  cluster_name = var.cluster_name
  public_apps  = var.public_apps
  depends_on   = [google_project_service.required]
}

module "operations" {
  source                = "./modules/operations"
  project_id            = var.project_id
  region                = var.region
  cluster_name          = module.gke_cluster.name
  backup_region         = var.backup_region
  backup_namespaces     = var.backup_namespaces
  notification_channels = var.notification_channels
  labels                = local.labels
}
