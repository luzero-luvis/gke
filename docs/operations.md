# Production acceptance and operations

## Before first traffic

1. Review the saved Terraform plan in the real project. Confirm billing, IAM, APIs, available versions/zones, non-overlapping IP space, and resource quotas. Check node quotas for the configured maximum plus surge and failure headroom.
2. Connect through `--dns-endpoint`. Inspect `gcloud container clusters describe` for disabled IP endpoints, private nodes, Workload Identity, Dataplane V2 and the configured release channel. Verify node VMs have no external addresses.
3. Run the README's server-side manifest dry runs, then inspect policies and controller status. Confirm a privileged test Pod is rejected in `apps`. Use a diagnostic image from the approved registry with the same restricted security settings for connectivity tests.
4. Test DNS and Google API access; confirm a Pod using KSA `app` can read its allowed secret, cannot read another secret, and cannot access Kubernetes Secrets. Do not print secret contents. Verify an unrelated Pod cannot reach the app or arbitrary internet endpoints.
5. Check `/healthz` and `/readyz`, graceful termination, startup time, resource requests, HPA scale-out and rollout under load. Confirm that the chosen image works as UID 10001 without writing outside `/tmp`.
6. Add valid Monitoring notification channels and trigger controlled incidents. Confirm CPU/memory/restart/NAT metrics exist and that alert filters match the actual project, region and cluster. Establish application latency/error SLOs, request-based alerts, and an external synthetic probe for public HTTPS.
7. Build, scan and attest an image in CI. Configure `binary_authorization_attestors`, verify an unsigned release is blocked and an attested release succeeds, and document emergency exception auditing. Review WAF preview logs against representative requests, set `waf_preview=false`, and confirm blocked test requests and working legitimate traffic.
8. Verify the first successful backup, namespace/volume coverage and alert delivery; then perform the restore drill below. Absence alerts cannot detect a backup series that has never appeared.

## Upgrades and daily operation

The default recurring maintenance window is 00:00–08:00 UTC on Saturday and Sunday. Keep sufficient eligible maintenance time when changing it. Emergency security upgrades can override maintenance scheduling. Test release-channel updates and deprecated API removals in staging before production, including the `latest` Pod Security policy that follows the cluster version.

Review Pending Pods, node autoscaler errors, quotas, workload restarts and KMS/identity failures. VPA is recommendation-only to avoid fighting the CPU-driven HPA. Read its recommendations and adjust requests through a reviewed rollout. Provisioning more nodes cannot fix exhausted address ranges or denied quotas.

Audit logs are enabled for GKE, Secret Manager, KMS and Artifact Registry Data Access operations. Admin Activity logs are supplied by Google Cloud. Project default log-bucket retention is not changed by this repository: set appropriate retention and a centralized sink with access controls where required. Avoid putting application secrets or personal data into logs.

Regional persistent disks use the optional `regional-balanced-retain` StorageClass. They replicate within a region and do not provide cross-region database recovery. `Retain` leaves volumes behind after PVC deletion; operators must manage their lifecycle. Prefer appropriate managed database services with their own backups/PITR for persistent application state.

## Restore drill and regional outage

Backups run at 00:00, 06:00, 12:00 and 18:00 UTC. The plan includes selected namespaces, Kubernetes Secrets and supported volume data, retains backups for 30 days and prevents deletion for the first seven days. The nominal schedule is not a guaranteed RPO: monitor job completion and measure actual recovery gaps. Backups need successful agent operation and do not include external databases or cloud infrastructure.

1. Choose an approved recovery region and create a separate project/state/CIDR allocation. Recreate the infrastructure from this repository with the recovery variables. Re-establish IAM, Artifact Registry access, secrets, KMS access and external data services as required.
2. Select a known-good Backup for GKE backup. Check completion status, workload coverage and volume backup status. Make sure required image digests and secret/key versions remain available.
3. Create a RestorePlan targeting the recovery cluster with explicit namespace conflict and volume restore policies. Choose supported cross-region volume restore settings for the actual volume types. Never first test restore into the serving namespace.
4. Restore application resources and supported volume data. Recover external databases using their service-specific process. Reconcile cloud IAM and deployment configuration from code. Restore of a backup is not restore of a VPC, GKE control plane, DNS zone or external secret store.
5. Test application behavior and data integrity in isolation. Compare recovery time and recovered data timestamps against the business-approved RTO/RPO. Record failures and repeat after correction.
6. Coordinate the traffic cutover only after validation; check certificates, Cloud Armor and DNS ownership. Existing DNS records and global IPs cannot be managed by two independent Terraform states. Use an explicit handoff/import or a separate, predesigned traffic-management layer.

No automatic cross-region failover is configured. Decide whether a cold rebuild, warm standby or active multi-region service meets the required recovery time and budget. See [Backup for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke) for supported resources and restore operations.

## Planned teardown

Remove Kubernetes routes/Gateways first and wait for their load balancers to be removed. Verify backups and data ownership. Cluster deletion protection and lifecycle guards on KMS, the registry, the backup plan and state bucket are intentional; remove them only in a reviewed retirement change. Keep state storage and decryption keys until recovery is no longer required. Do not disable GKE/Compute APIs while resources still depend on them.
