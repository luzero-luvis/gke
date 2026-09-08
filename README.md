# Modular production GKE foundation

Terraform for a regional GKE Standard cluster, organized like the companion EKS project. The cluster module wraps [`terraform-google-modules/kubernetes-engine/google` v45.0.0](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v45.0.0). This repository contains infrastructure and workload templates; no Google Cloud resources have been deployed.

```text
.
├── bootstrap/
│   ├── main.tf                 # Protected, versioned GCS state bucket
│   ├── outputs.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
├── terraform/
│   ├── main.tf                 # API enablement and module composition
│   ├── data.tf
│   ├── locals.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── versions.tf
│   ├── backend.hcl.example
│   ├── terraform.tfvars.example
│   ├── tests/
│   └── modules/                # Each module has variables, outputs, versions
│       ├── network/            # Custom VPC, ranges, NAT, private API DNS
│       ├── security/           # Node IAM, KMS, registry, audit, image policy
│       ├── gke-cluster/        # Regional control plane and managed node pools
│       ├── workload-identity/  # Per-secret Kubernetes principal grants
│       ├── https-gateway/      # Cloud Armor, IP, certificate, public DNS, TLS
│       └── operations/         # Backups and Cloud Monitoring alerts
├── workloads/templates/       # Namespace, network rules, workload, Gateway
├── scripts/                   # Render manifests and inspect effective plans
├── tests/                     # Workload behavior and security checks
└── docs/
    ├── architecture.md
    └── operations.md
```

GKE manages the load-balancer controller, HPA/VPA support, CSI driver, and node autoscaler. The upstream cluster module owns the managed node pools in this design. Workload Identity Federation supplies the role that IRSA serves in the EKS project. There is no AWS ALB controller or Karpenter installation.

## What is configured

| Area | Implementation |
| --- | --- |
| Availability | Regional control plane; three zones; at least one on-demand node per zone; auto-repair; managed upgrades; surge capacity |
| Network | VPC-native, separate node/Pod/Service ranges; private nodes; DNS-only control-plane access; Dataplane V2; Cloud DNS and local DNS cache; Private Google Access; scoped Cloud NAT |
| Identity | Dedicated node identity; repository-scoped image pulls; Workload Identity Federation; resource-scoped Secret Manager grants; optional Google Groups RBAC |
| Security | Shielded nodes and Secure Boot; metadata hardening; disabled kubelet read-only port; rotating KMS key for Kubernetes Secrets; image scanning; audit logs |
| Workloads | Restricted Pod Security; non-root read-only containers; default-deny ingress and egress; quotas; probes; three replicas; topology spreading; HPA; PDB; VPA recommendations |
| HTTPS, optional | Gateway API; container-native backends; Certificate Manager; global IP; TLS 1.2+; Cloud Armor rate limiting; WAF rules; backend health checks and logs |
| Operations | Managed Prometheus; system/control-plane/workload telemetry; CPU, memory, restarts, NAT and backup alerts; backups every six hours in a second region |
| State | Separate bootstrap; GCS locking, version history, soft delete, public-access prevention; deletion guards; committed provider lock files |

**Before production traffic:** supply alert channels, tune capacity and cost limits, validate workload behavior, perform a restore drill, and enable image-attestation and WAF enforcement after their prerequisites are ready. The `release_readiness` output makes these gaps visible. The default Binary Authorization policy audits would-be rejections; WAF signatures default to preview. Neither is represented as blocking protection until configured to enforce.

## 1. Configure state

Prerequisites: Terraform 1.9 or newer (below 2.0), Google Cloud CLI, `gke-gcloud-auth-plugin`, `kubectl`, and Python 3. Use a dedicated billing-enabled project per environment. The bootstrap administration project needs the Storage API enabled. Authenticate using ADC or an impersonated deployment identity; do not create JSON service-account keys.

```sh
gcloud auth application-default login
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
# Edit the administration project, state bucket name, location, and state users.
terraform -chdir=bootstrap init
terraform -chdir=bootstrap plan -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
```

Bootstrap initially uses local state. Keep it encrypted and backed up; to store it remotely, add `terraform { backend "gcs" {} }` in `bootstrap/backend.tf`, then migrate with `terraform -chdir=bootstrap init -migrate-state -backend-config="bucket=YOUR_STATE_BUCKET" -backend-config="prefix=bootstrap"`. Use a distinct prefix from the infrastructure root. State and plan files are ignored by Git.

## 2. Configure infrastructure

```sh
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp terraform/backend.hcl.example terraform/backend.hcl
# Edit both files with real environment values.
terraform -chdir=terraform init -backend-config=backend.hcl
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=production.tfplan
# Review the plan, resource counts, permissions, regions, and costs.
terraform -chdir=terraform apply production.tfplan
terraform -chdir=terraform output release_readiness
terraform -chdir=terraform output -raw get_credentials_command
```

Run the printed credentials command with your authorized identity. It includes `--dns-endpoint`; no bastion is needed for this configuration. DNS endpoint reachability is protected by IAM and Kubernetes authorization. It is reachable through Google APIs and is not an implemented VPC Service Controls perimeter.

The example uses Mumbai with a Delhi backup location as editable placeholders, not an inferred residency requirement. Choose available zones and a supported backup location for your project. This root creates a dedicated VPC. Adopting an existing VPC/Shared VPC requires changing the network module interface, host-project IAM and firewall ownership before applying.

The deployment identity needs permissions for the resources in its plan: API enablement, GKE administration, VPC/DNS/NAT management, service account creation and `actAs`, scoped project IAM changes, KMS, Artifact Registry, Binary Authorization, backups, and monitoring; public HTTPS additionally needs Certificate Manager and public-zone access. Separate deployment privileges from runtime privileges. Resolve these against your organization's IAM policy; the modules do not grant themselves owner/editor. Import and reconcile existing resources, especially project-wide Binary Authorization and per-service audit configurations, before using an existing project.

Use separate checkouts/working directories, projects, CIDR allocations, tfvars and state prefixes for staging and production. Avoid switching live backend state in one initialized directory.

## 3. Deploy your application

Build and scan an image in the created repository. The application contract is HTTP on port 8080, `/healthz` for local process health, `/readyz` for serving readiness, UID/GID 10001, a read-only root filesystem with writable `/tmp`, and graceful SIGTERM handling within 60 seconds. Adjust the templates to your real app before deploying. Liveness must not depend on downstream database availability.

```sh
terraform -chdir=terraform output -json workload_config > /tmp/gke-workload-config.json
python3 scripts/render-workloads.py \
  --config /tmp/gke-workload-config.json \
  --image 'REGION-docker.pkg.dev/PROJECT/REPOSITORY/app@sha256:REAL_64_CHARACTER_DIGEST' \
  --output workloads/rendered/release-001
```

Use a fresh output directory for each render; this prevents stale public routes from surviving a private render. Rendering requires a real-format immutable digest from the Terraform-created registry. It does not prove the image exists or has passed scanning; those are CI/release responsibilities.

Review the files, select the intended `kubectl` context, then apply the namespace controls before the application:

```sh
kubectl config current-context
kubectl apply --server-side --dry-run=server -f workloads/rendered/release-001/foundation.yaml
kubectl apply --server-side -f workloads/rendered/release-001/foundation.yaml
kubectl apply --server-side --dry-run=server -f workloads/rendered/release-001/application.yaml
kubectl apply --server-side -f workloads/rendered/release-001/application.yaml
kubectl -n apps rollout status deployment/app --timeout=10m
kubectl -n apps get pods -o wide
kubectl -n apps get hpa,pdb,vpa
```

On subsequent releases, let HPA own `spec.replicas`: omit that field from the Deployment manifest after the initial deployment, or configure your GitOps controller to ignore it. Reapplying a fixed replica count can fight the HPA.

By default, ingress is denied, including from other apps in the same namespace. Add narrow namespace-and-Pod selectors for real service dependencies on both sending and receiving sides. Egress permits only DNS, the Dataplane V2 metadata server, and HTTPS to the private Google API VIP. Add reviewed rules for databases and external services. Cloud NAT provides connectivity; it does not create these Pod egress permissions.

Use `secret_access` for existing Secret Manager secrets and retrieve them using your app's Google SDK with ADC. The optional Secret Manager CSI add-on is enabled, but mounting a secret requires your own SecretProviderClass and volume configuration. The supplied app service account has no Kubernetes RBAC permissions and no automatic API token mount. For read-only human access, configure Google Groups for RBAC, set `cluster_access_members`, and render with `--reader-group=readers@your-domain`; apply the resulting `reader-rbac.json` separately.

## 4. Enable public HTTPS, when needed

Set `public_app` using an owned hostname and an existing public Cloud DNS zone in the same project, apply the reviewed infrastructure plan, and render a new release directory. The renderer adds edge policy and routing files. Apply policies before creating the route:

```sh
kubectl apply --server-side --dry-run=server -f workloads/rendered/release-002/edge-policy.yaml
kubectl apply --server-side -f workloads/rendered/release-002/edge-policy.yaml
kubectl apply --server-side --dry-run=server -f workloads/rendered/release-002/edge-routing.yaml
kubectl apply --server-side -f workloads/rendered/release-002/edge-routing.yaml
kubectl -n apps get gateway,httproute,gcpbackendpolicy,gcpgatewaypolicy,healthcheckpolicy
kubectl -n apps describe gateway app
```

Wait for certificate issuance, Gateway `Programmed`, route acceptance/resolved references, healthy backends, and successful policy status. Verify the effective backend has the expected Cloud Armor policy and the proxy has the TLS policy. Controllers reconcile asynchronously; do not direct production users until the checks pass. The Gateway listens only on HTTPS. Authentication/authorization inside your application remains your responsibility.

The GKE Gateway controller manages NEGs and associated firewall rules in this dedicated VPC. Do not add Ingress NEG annotations or an AWS load-balancer controller. The Pod ingress exception permits Google's load-balancer/health-check ranges on port 8080 only. For an internal or regional Gateway, change both the load-balancer design and source ranges.

When removing HTTPS, remove the Kubernetes HTTPRoute/Gateway first, wait for managed load-balancer cleanup, then remove Terraform's certificate/IP/DNS resources. Rendering a private release does not delete a previously applied public route.

## Validation

```sh
terraform fmt -check -recursive
terraform -chdir=bootstrap init -backend=false
terraform -chdir=bootstrap validate
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
terraform -chdir=terraform test -json -verbose > /tmp/gke-tests.jsonl
python3 scripts/check-terraform-plan.py /tmp/gke-tests.jsonl
python3 -m pip install -r requirements-dev.txt
python3 -m unittest discover -s tests -v
```

These tests use mock cloud providers and inspect the expanded upstream cluster/node resources. They also check workload policy relationships, HPA rollout headroom, and public/private rendering. They do not validate real project quotas, IAM propagation, regional service support, certificate issuance, CRD/controller behavior, or recovery. Run server-side dry runs and the [operational acceptance checks](docs/operations.md) in staging.

The pinned [v45.0.0 module release](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/releases/tag/v45.0.0) fixes the deprecated IP-masquerade ConfigMap resource by using `kubernetes_config_map_v1`. It requires Google provider 7.39.0 or newer within version 7; the committed lock file selects 7.46.1. After pulling this update, run `terraform -chdir=terraform init` to download the new module, then validate and generate a fresh saved plan. Keep the provider lock file; editing the downloaded `.terraform/modules` cache is not a durable fix. This foundation leaves `configure_ip_masq` disabled, so it has no IP-masquerade ConfigMap state to migrate.

The GitHub Actions workflow runs these checks with read-only repository permissions and no cloud credentials. Actions are pinned by commit. Production deployment should use a separate, protected pipeline with short-lived federation credentials and a reviewed saved plan.

See the [architecture and guidance mapping](docs/architecture.md) for assumptions, costs and organization-level decisions.
