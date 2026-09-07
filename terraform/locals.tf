locals {
  labels = { environment = var.environment, managed_by = "terraform", cluster = var.cluster_name }
  services = toset([
    "artifactregistry.googleapis.com", "binaryauthorization.googleapis.com",
    "cloudkms.googleapis.com", "compute.googleapis.com", "container.googleapis.com",
    "containeranalysis.googleapis.com", "containerscanning.googleapis.com",
    "dns.googleapis.com", "gkebackup.googleapis.com", "iam.googleapis.com",
    "iamcredentials.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com",
    "secretmanager.googleapis.com", "serviceusage.googleapis.com", "sts.googleapis.com",
    "certificatemanager.googleapis.com"
  ])
}
