locals {
  cluster_filter = "resource.labels.project_id = \"${var.project_id}\" AND resource.labels.location = \"${var.region}\" AND resource.labels.cluster_name = \"${var.cluster_name}\""
  backup_filter  = "resource.type = \"gkebackup.googleapis.com/BackupPlan\" AND resource.labels.project_id = \"${var.project_id}\" AND resource.labels.location = \"${var.backup_region}\" AND resource.labels.backup_plan_id = \"${google_gke_backup_backup_plan.apps.name}\""
  thresholds = {
    node_cpu = {
      filter    = "resource.type = \"k8s_node\" AND ${local.cluster_filter} AND metric.type = \"kubernetes.io/node/cpu/allocatable_utilization\""
      threshold = 0.85
      duration  = "900s"
      aligner   = "ALIGN_MEAN"
      runbook   = "Inspect node capacity, Pending Pods, autoscaler events, quotas, and CPU requests. Reserve capacity for zone loss and upgrades."
    }
    node_memory = {
      filter    = "resource.type = \"k8s_node\" AND ${local.cluster_filter} AND metric.type = \"kubernetes.io/node/memory/allocatable_utilization\" AND metric.labels.memory_type = \"non-evictable\""
      threshold = 0.85
      duration  = "900s"
      aligner   = "ALIGN_MEAN"
      runbook   = "Inspect memory requests and OOM events. Use VPA recommendations; diagnose leaks before increasing limits."
    }
    container_restarts = {
      filter    = "resource.type = \"k8s_container\" AND ${local.cluster_filter} AND metric.type = \"kubernetes.io/container/restart_count\""
      threshold = 3
      duration  = "0s"
      aligner   = "ALIGN_DELTA"
      runbook   = "Inspect previous container logs, OOMKilled events, probes, and the latest rollout. More than 3 restarts occurred in a 5-minute window."
    }
    nat_drops = {
      filter    = "resource.type = \"nat_gateway\" AND resource.labels.project_id = \"${var.project_id}\" AND resource.labels.region = \"${var.region}\" AND resource.labels.gateway_name = \"${var.cluster_name}-nat\" AND metric.type = \"router.googleapis.com/nat/dropped_sent_packets_count\""
      threshold = 0
      duration  = "300s"
      aligner   = "ALIGN_SUM"
      runbook   = "Inspect NAT error logs, port usage, connection pooling, and NAT IP quota; check whether max_ports_per_vm needs adjustment."
    }
    backup_failed = {
      filter    = "${local.backup_filter} AND metric.type = \"gkebackup.googleapis.com/backup_completion_times\" AND metric.labels.state = \"FAILED\""
      threshold = 0
      duration  = "0s"
      aligner   = "ALIGN_PERCENTILE_99"
      runbook   = "Inspect the failed Backup for GKE job and agent health. Resolve the cause and create a fresh backup; verify volume and namespace coverage."
    }
  }
}

resource "google_monitoring_alert_policy" "threshold" {
  for_each              = local.thresholds
  display_name          = "${var.cluster_name}: ${each.key}"
  combiner              = "OR"
  notification_channels = var.notification_channels
  user_labels           = var.labels
  documentation {
    content   = each.value.runbook
    mime_type = "text/markdown"
  }
  conditions {
    display_name = each.key
    condition_threshold {
      filter          = each.value.filter
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = each.value.duration
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = each.value.aligner
      }
      trigger { count = 1 }
    }
  }
  alert_strategy { auto_close = "604800s" }
}

resource "google_monitoring_alert_policy" "backup_missing" {
  display_name          = "${var.cluster_name}: no successful backup for 12 hours"
  combiner              = "OR"
  notification_channels = var.notification_channels
  user_labels           = var.labels
  documentation {
    content   = "Backups run every six hours. Inspect agent health, the schedule, IAM, and recent backup jobs. Verify the first successful backup manually: absence alerts require an observed time series."
    mime_type = "text/markdown"
  }
  conditions {
    display_name = "Missing successful backups"
    condition_absent {
      filter   = "${local.backup_filter} AND metric.type = \"gkebackup.googleapis.com/backup_completion_times\" AND metric.labels.state = \"SUCCEEDED\""
      duration = "43200s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
      trigger { count = 1 }
    }
  }
}
