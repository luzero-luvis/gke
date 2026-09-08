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
