# GCP CLI & Terraform Authentication Setup

How to install `gcloud`, authenticate, and grant a limited-access account
enough IAM to run Terraform in this repo — without using a service account
key.

## Why no service account key

Terraform can authenticate as your own Google account via Application
Default Credentials (ADC). This avoids creating a long-lived JSON key that
would need to be stored and rotated. Options, in order of preference:

1. **Your user account via ADC** (this doc) — good for local development.
2. **Service account impersonation** (`roles/iam.serviceAccountUser` +
   `gcloud auth application-default login --impersonate-service-account`) —
   use when Terraform must act as a specific robot identity.
3. **Workload Identity Federation** — use for CI/CD (GitHub Actions,
   GitLab CI, etc.), never a downloaded key there either.
4. **Service account JSON key** — avoid. Long-lived credential, risk if
   leaked.

## 1. Install the Google Cloud SDK

```
curl https://sdk.cloud.google.com | bash
```

If a previous partial install already exists at `~/google-cloud-sdk`, run
the installer directly instead of the curl wrapper:

```
~/google-cloud-sdk/install.sh --usage-reporting false --command-completion true --path-update true --quiet
```

This updates your shell rc file (e.g. `~/.zshrc`) to add `gcloud` to
`PATH`. Start a new shell (or `source ~/.zshrc`) afterward.

Verify:

```
gcloud --version
```

## 2. Log in to gcloud (CLI identity)

This sets the identity `gcloud` commands run as (`gcloud projects list`,
etc.) — separate from the credentials Terraform uses.

```
gcloud auth login <you>@gmail.com
```

Opens a browser OAuth flow. **If your browser is already signed into a
different Google account**, it may silently authenticate as that account
instead of prompting. To force the correct account, either:

- Use "Add another account" in the browser's account picker first, or
- Use the manual flow so you control which browser/session opens the URL:

  ```
  gcloud auth login --no-launch-browser
  ```

  Paste the printed URL into an incognito window signed in as the
  intended account, approve, then paste the resulting code back into the
  terminal.

Confirm the active account:

```
gcloud config get-value account
```

## 3. Set the target project

```
gcloud config set project <PROJECT_ID>
```

List projects your account can see:

```
gcloud projects list --format="table(projectId,name,projectNumber)"
```

## 4. Check / enable billing

Terraform will create billable resources (GKE, Compute, KMS, etc.), so the
project needs an **open** billing account linked.

Check billing accounts visible to your account:

```
gcloud billing accounts list --format="table(name,displayName,open)"
```

Check whether the project has billing enabled:

```
gcloud billing projects describe <PROJECT_ID> --format="value(billingEnabled)"
```

**If `open: false` on the billing account:** this cannot be fixed via
`gcloud` — there is no CLI command to add/verify a payment method (Google
only exposes this through the Console UI for fraud/security reasons).

1. Go to `https://console.cloud.google.com/billing/<BILLING_ACCOUNT_ID>`
2. Add/confirm a payment method to reopen the account.
3. A prepayment/verification charge may take up to 24 hours to clear and
   reflect as `open: true` — do not pay twice, just wait.

Once open, link it to the project:

```
gcloud billing projects link <PROJECT_ID> --billing-account=<BILLING_ACCOUNT_ID>
```

## 5. Grant IAM roles for a limited-access account

Rather than using `roles/owner`, grant only what this repo's Terraform
config actually creates. Determined by scanning `terraform/main.tf` and
every module under `terraform/modules/*` for `resource "..."` blocks:

| Role | Why |
|---|---|
| `roles/container.admin` | GKE cluster |
| `roles/compute.networkAdmin` | VPC, subnets, router, Cloud NAT |
| `roles/compute.securityAdmin` | Cloud Armor security policy, SSL policy |
| `roles/artifactregistry.admin` | Artifact Registry repo + IAM |
| `roles/dns.admin` | Cloud DNS managed zone, records |
| `roles/certificatemanager.editor` | Certificate Manager certs/maps/DNS auth |
| `roles/cloudkms.admin` | KMS key ring, crypto keys, IAM |
| `roles/gkebackup.admin` | Backup for GKE plan |
| `roles/monitoring.editor` | Alert policies |
| `roles/iam.serviceAccountAdmin` | Creates GKE workload identity service accounts |
| `roles/resourcemanager.projectIamAdmin` | Grants IAM bindings (`google_project_iam_member`, audit config) |
| `roles/secretmanager.admin` | Secret Manager IAM bindings on existing secrets |
| `roles/serviceusage.serviceUsageAdmin` | Enables required GCP APIs |
| `roles/iam.serviceAccountUser` | Lets Terraform/GKE act as the service accounts it creates |
| `roles/binaryauthorization.policyAdmin` | Sets the project's Binary Authorization admission policy |
| `roles/storage.admin` | Creates the Terraform state bucket (`bootstrap/`) |

Grant them (run as an account that already has `roles/owner` or
`roles/resourcemanager.projectIamAdmin`, e.g. the project creator):

```bash
PROJECT=<PROJECT_ID>
MEMBER=user:<limited-access-account>@gmail.com
ROLES=(
  roles/container.admin
  roles/compute.networkAdmin
  roles/compute.securityAdmin
  roles/artifactregistry.admin
  roles/dns.admin
  roles/certificatemanager.editor
  roles/cloudkms.admin
  roles/gkebackup.admin
  roles/monitoring.editor
  roles/iam.serviceAccountAdmin
  roles/resourcemanager.projectIamAdmin
  roles/secretmanager.admin
  roles/serviceusage.serviceUsageAdmin
  roles/iam.serviceAccountUser
  roles/binaryauthorization.policyAdmin
  roles/storage.admin
)
for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="$MEMBER" \
    --role="$ROLE" \
    --condition=None
done
```

Verify:

```
gcloud projects get-iam-policy <PROJECT_ID> \
  --flatten="bindings[].members" \
  --filter="bindings.members:<limited-access-account>@gmail.com" \
  --format="table(bindings.role)"
```

## 6. Switch gcloud and ADC to the limited-access account

Two separate credential stores need updating:

- `gcloud config` — identity for `gcloud` commands themselves.
- ADC (`~/.config/gcloud/application_default_credentials.json`) — identity
  Terraform (and any Google client library) actually authenticates as.

```
gcloud config set account <limited-access-account>@gmail.com
gcloud config set project <PROJECT_ID>
gcloud auth application-default login --no-launch-browser
```

Same account-mismatch risk as step 2 applies here — use
`--no-launch-browser` and an incognito window if your default browser
session is signed into a different Google account:

1. Command prints an `https://accounts.google.com/o/oauth2/auth...` URL.
2. Open it in an incognito window, sign in as the limited-access account,
   click Allow.
3. Copy the verification code shown and paste it back at the
   `Enter the verification code` prompt.

Set the quota project for ADC (needed so billing/quota is attributed
correctly, especially for an account without `roles/owner`):

```
gcloud auth application-default set-quota-project <PROJECT_ID>
```

**Verify which identity ADC actually resolves to** (don't trust
`gcloud config get-value account` alone — that's the CLI identity, not
necessarily what ADC saved):

```bash
TOKEN=$(gcloud auth application-default print-access-token)
curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$TOKEN" | grep email
```

## 7. Configure Terraform variables

```
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `project_id` to the real project, and review every other value —
`terraform/variables.tf` documents constraints and validation rules for
each. Notably:

- `project_id` must be an **existing, billing-enabled** project.
- `backup_region` must differ from `region`.
- `max_nodes_per_zone` × 3 zones × `machine_type` size drives cost — the
  `terraform.tfvars.example` defaults are production-sized (up to 30 nodes
  of `e2-standard-4` + 3 surge). Scale down for testing, e.g.:

  ```hcl
  environment         = "development"
  machine_type        = "e2-medium"
  max_nodes_per_zone  = 2   # minimum allowed by validation
  ```

## 8. Run Terraform

```
cd terraform
terraform init
terraform plan
```

`terraform plan` does not provision billable resources, so it can succeed
even before billing finishes activating on the project. `terraform apply`
will fail on API-enablement steps until billing is confirmed `open: true`
and linked to the project (step 4).

## Reference: full command sequence

```bash
# Install
curl https://sdk.cloud.google.com | bash
~/google-cloud-sdk/install.sh --usage-reporting false --command-completion true --path-update true --quiet

# CLI login (limited-access account)
gcloud auth login --no-launch-browser   # paste code from incognito window

# Project + billing
gcloud config set project <PROJECT_ID>
gcloud billing accounts list --format="table(name,displayName,open)"
gcloud billing projects describe <PROJECT_ID> --format="value(billingEnabled)"
# (reopen billing account in Console if closed, then:)
gcloud billing projects link <PROJECT_ID> --billing-account=<BILLING_ACCOUNT_ID>

# Grant limited IAM roles (run as an existing Owner/IAM admin)
# — see role table and loop above —

# Switch this account to active + ADC
gcloud config set account <limited-access-account>@gmail.com
gcloud config set project <PROJECT_ID>
gcloud auth application-default login --no-launch-browser
gcloud auth application-default set-quota-project <PROJECT_ID>

# Confirm ADC identity
TOKEN=$(gcloud auth application-default print-access-token)
curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$TOKEN" | grep email

# Terraform
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform.tfvars
cd terraform
terraform init
terraform plan
```

## 9. Troubleshooting

### Missing an IAM role mid-apply

If a limited-access account is missing a role, `apply` fails partway with a
`403 Permission '...' denied` error on one specific resource. Grant the
missing role (`gcloud projects add-iam-policy-binding`, same pattern as
step 5) and re-run `apply` — it resumes from where it left off, it does
not restart from scratch. Two roles this repo's own testing missed on the
first pass: `roles/binaryauthorization.policyAdmin` (for
`google_binary_authorization_policy`) and `roles/storage.admin` (for the
`bootstrap/` state bucket) — both are already included in the table/loop
above now.

### `GCE_STOCKOUT` / `ZONE_RESOURCE_POOL_EXHAUSTED` during cluster creation

GCP had no spare capacity for the requested machine type in one zone.
This is Google's own physical capacity limit, not a quota, billing, or
config problem — retrying with a different `machine_type` doesn't
necessarily help if it's the *zone* that's constrained rather than the
instance family. Signs it's zone-specific: the same zone fails across
multiple different machine types.

There's no way to cancel a `CREATE_CLUSTER` operation once it's running
(`gcloud container operations cancel` explicitly rejects it), and you
can't delete the cluster while that operation is still `RUNNING`
(`Cluster is running incompatible operation`). GKE's own instance-group
retry loop can keep trying for anywhere from ~30 minutes to a few hours
before it gives up on its own — there's no documented fixed timeout, and
no CLI/API override. Options once it finally reports `DONE` with the
stockout error in
`gcloud container operations describe <op> --region=<region> --format="yaml(status,error)"`:

```
gcloud container clusters delete <cluster> --region=<region> --quiet
```

Then either wait longer and retry the same zones, or route around the bad
zone:

- **Drop to 2 zones** in the same region if only one zone is affected —
  requires loosening the `length(var.zones) == 3` validation in both
  `terraform/variables.tf` and `terraform/modules/gke-cluster/variables.tf`
  to `>= 2`, then setting `zones` in `terraform.tfvars` to the two healthy
  zones. Slightly reduces HA versus 3 zones.
- **Switch region entirely** — no code changes needed, just update
  `region`, `zones`, and `backup_region` in `terraform.tfvars`. Better if
  the whole region looks constrained, not just one zone.

Since the cluster never finished creating, it's never written into
Terraform state — `terraform destroy` has nothing to target. Cleanup has
to go through `gcloud` directly in this specific case.

### "tainted" resource wants to destroy+recreate something that's actually fine

If an `apply` gets interrupted (Ctrl+C, a crash) right as a resource
finishes creating, Terraform marks it **tainted** in state — a
just-in-case flag meaning "I can't confirm this came out right, destroy
and recreate it next time." If you've confirmed via `gcloud`/Console that
the real resource is healthy and matches config, don't let Terraform
destroy it — untaint instead:

```
terraform untaint '<resource address from `terraform plan`>'
```

Re-run `terraform plan` afterward; it should show `0 to destroy` for that
resource.

### `google_monitoring_alert_policy` rejects the aligner with a 400 error

Example: `Field aggregation.perSeriesAligner had an invalid value of
"ALIGN_COUNT": The aligner cannot be applied to metrics with kind DELTA
and value type DISTRIBUTION.` Not every `per_series_aligner` works with
every GCP metric — it depends on that specific metric's `metricKind`
(GAUGE/DELTA/CUMULATIVE) and `valueType` (INT64/DOUBLE/DISTRIBUTION/...).
Guessing aligners by trial and error against the live API wastes time and
API calls; check the actual descriptor first:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/<PROJECT_ID>/metricDescriptors/<metric.type, literal slash not encoded>" \
  | python3 -m json.tool
```

For `gkebackup.googleapis.com/backup_completion_times` specifically
(`DELTA` + `DISTRIBUTION`): `ALIGN_COUNT` and `ALIGN_MEAN` are both
rejected (those reducers are restricted to GAUGE/CUMULATIVE kinds for
distribution-valued metrics); `ALIGN_PERCENTILE_99` works and produces a
scalar `DOUBLE` — since every completion-time sample is a positive
duration, a `> 0` threshold still trips correctly whenever any matching
event (a failed backup, or presence-check via `condition_absent`) exists
in the window. `condition_absent` blocks need their own `aggregations {}`
too — it's not inherited from anywhere, and omitting it fails with
`Request was missing field aggregation.perSeriesAligner`.

### Perpetual no-op diff on `google_container_cluster.monitoring_config`

`terraform plan` may keep showing `enable_components` changing even
right after a clean `apply`, e.g. `DAEMONSET` moving position in the
list. This is a known list-vs-set mismatch: GKE's API doesn't guarantee
it returns this field in the same order it was sent, but Terraform's
schema treats it as an ordered list, not a set. The set of components is
identical either way — harmless, cosmetic, safe to ignore. An empty
`master_authorized_networks_config {}` block appearing as "added" every
plan is the same story.

## 10. Before this serves real traffic

The `release_readiness` Terraform output reports what's still
unconfigured for production, computed directly from your variables — it
is not just documentation, it's live feedback on the current
`terraform.tfvars`:

```
terraform output release_readiness
```

Checklist, in the order this repo's variables expose them:

- `notification_channels = []` → `alert_delivery_configured: false`.
  Alerts fire into the Monitoring console but page no one. Supply real
  channel resource names.
- `binary_authorization_attestors = []` → `attestation_enforced: false`.
  Binary Authorization runs audit-only (logs violations, blocks nothing)
  until attestors are supplied.
- `public_app = null` → `public_https_configured: false`,
  `waf_enforced: false`. No public HTTPS endpoint or Cloud Armor
  protection is configured until this is set.
- `requires_load_test` / `requires_restore_drill` are always `true` —
  the module is explicit that a load test and an actual Backup-for-GKE
  restore drill are manual steps outside Terraform's scope, not
  something `apply` can satisfy for you.
- Bump `environment`, `machine_type`, and `max_nodes_per_zone` up from a
  scaled-down test config once ready — see step 7 for the sizing
  trade-off.
