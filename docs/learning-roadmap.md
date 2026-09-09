# Learning Roadmap

Every file touched this session, in the order it was actually built/read.
Two repos: `luvis-in/gke` (the platform) and `sirpi-in/mts-ijp` (the app on
top of it — paths in step 13 onward are relative to that repo).

## 1. GCP CLI & auth (no files — CLI only)
- `gcloud auth login` vs `gcloud auth application-default login`
- Reference written afterward: `docs/gcp-auth-setup.md`

## 2. Terraform state backend
- [ ] `bootstrap/providers.tf`
- [ ] `bootstrap/variables.tf`
- [ ] `bootstrap/main.tf`
- [ ] `bootstrap/outputs.tf`
- [ ] `bootstrap/terraform.tfvars.example`
- [ ] `bootstrap/terraform.tfvars` — created (gitignored, real bucket name/project)

## 3. Root Terraform module
- [ ] `terraform/versions.tf`
- [ ] `terraform/variables.tf`
- [ ] `terraform/locals.tf`
- [ ] `terraform/data.tf`
- [ ] `terraform/main.tf`
- [ ] `terraform/outputs.tf`
- [ ] `terraform/terraform.tfvars.example`
- [ ] `terraform/terraform.tfvars` — created (gitignored)

## 4. Network module
- [ ] `terraform/modules/network/variables.tf`
- [ ] `terraform/modules/network/main.tf`
- [ ] `terraform/modules/network/outputs.tf`

## 5. Security module
- [ ] `terraform/modules/security/variables.tf`
- [ ] `terraform/modules/security/main.tf`
- [ ] `terraform/modules/security/outputs.tf`

## 6. GKE cluster module
- [ ] `terraform/modules/gke-cluster/variables.tf` — edited (3-zone → 2-zone validation)
- [ ] `terraform/modules/gke-cluster/main.tf`
- [ ] `terraform/modules/gke-cluster/outputs.tf`
- [ ] `terraform/modules/gke-cluster/versions.tf`

## 7. Workload Identity module
- [ ] `terraform/modules/workload-identity/variables.tf`
- [ ] `terraform/modules/workload-identity/main.tf`
- [ ] `terraform/modules/workload-identity/outputs.tf`

## 8. Operations module
- [ ] `terraform/modules/operations/variables.tf`
- [ ] `terraform/modules/operations/monitoring.tf` — edited (`ALIGN_PERCENTILE_99` fix)
- [ ] `terraform/modules/operations/main.tf` (backup plan)
- [ ] `terraform/modules/operations/outputs.tf`

## 9. HTTPS Gateway module — the shared-LB refactor
- [ ] `terraform/modules/https-gateway/variables.tf` — edited (`public_app` → `public_apps` map)
- [ ] `terraform/modules/https-gateway/main.tf` — rewritten
- [ ] `terraform/modules/https-gateway/outputs.tf` — edited

## 10. Root wiring for the above modules
- [ ] `terraform/main.tf` — edited (`public_apps` passthrough)
- [ ] `terraform/outputs.tf` — edited (`workload_config.gateway`, `release_readiness`)
- [ ] `terraform/variables.tf` — edited (`public_apps` variable)

## 11. Terraform tests
- [ ] `terraform/tests/foundation.tftest.hcl` — edited (multi-app test case added, tfvars-leak fix)

## 12. Kubernetes workload templates
- [ ] `workloads/templates/foundation.yaml`
- [ ] `workloads/templates/application.yaml`
- [ ] `workloads/templates/gateway.yaml` — new (split out of edge-routing.yaml), then edited (`allowedRoutes: All`)
- [ ] `workloads/templates/edge-routing.yaml` — edited (trimmed to just HTTPRoute)
- [ ] `workloads/templates/edge-policy.yaml` — edited (GCPGatewayPolicy moved out)

## 13. Render script + its tests
- [ ] `scripts/render-workloads.py` — edited (`gateway` config shape, `--app` flag)
- [ ] `scripts/check-terraform-plan.py`
- [ ] `tests/test_workloads.py` — edited (multi-app test added)

## 14. Repo docs (this repo)
- [ ] `README.md` — edited (doc links)
- [ ] `docs/architecture.md`
- [ ] `docs/operations.md`
- [ ] `docs/uber-inspired-architecture.md`
- [ ] `docs/gcp-auth-setup.md` — created, then extended (troubleshooting, readiness checklist)
- [ ] `docs/deployment-log.md` — created
- [ ] `docs/mts-ijp-deployment.md` — created
- [ ] `.gitignore`

## 15. mts-ijp app source (read for context, other repo)
- [ ] `docker-compose.yml`
- [ ] `.env` / `.env.example`
- [ ] `.github/workflows/ci-cd.yml`

## 16. mts-ijp Helm chart — read the existing pieces first
- [ ] `charts/mts-ijp/Chart.yaml`
- [ ] `charts/mts-ijp/values.yaml`
- [ ] `charts/mts-ijp/templates/_helpers.tpl`
- [ ] `charts/mts-ijp/templates/deployment.yaml` — edited (CSI volume/mount, sync-controller label)
- [ ] `charts/mts-ijp/templates/service.yaml`
- [ ] `charts/mts-ijp/templates/pvc.yaml`
- [ ] `charts/mts-ijp/templates/pdb.yaml`
- [ ] `charts/mts-ijp/templates/NOTES.txt`

## 17. mts-ijp Helm chart — new templates built this session
- [ ] `charts/mts-ijp/templates/httproute.yaml` — new
- [ ] `charts/mts-ijp/templates/secretproviderclass.yaml` — new

## 18. mts-ijp per-service values (all new)
- [ ] `charts/values/otp.yaml`
- [ ] `charts/values/gateway.yaml`
- [ ] `charts/values/backend.yaml`
- [ ] `charts/values/mobility-api.yaml`
- [ ] `charts/values/ondc-adapter.yaml`
- [ ] `charts/values/wa-bot.yaml`
- [ ] `charts/values/frontend.yaml`

## 19. mts-ijp app code — read for exact routes/ports before writing values
- [ ] `backend/Dockerfile`
- [ ] `backend/app.py`
- [ ] `backend/jwtutil.py`
- [ ] `backend/gateway.Dockerfile`
- [ ] `backend/gateway.py` — **edited** (`self.close_connection = True` fix)
- [ ] `mobility-api/Dockerfile`
- [ ] `mobility-api/app/main.py`
- [ ] `mobility-api/app/api/v1/endpoints/health.py`
- [ ] `mobility-api/app/api/v1/endpoints/mobility.py`
- [ ] `adapter/Dockerfile`
- [ ] `adapter/app.py`
- [ ] `frontend/Dockerfile`
- [ ] `frontend/serve.cjs`
- [ ] `wa-bot/Dockerfile`
- [ ] `wa-bot/server.js`
- [ ] `ondc-workbench-simulator/Dockerfile`

## 20. Debugging log — the 13 real bugs, all found across steps 16–19
- [ ] `docs/mts-ijp-deployment.md` §9 — read this once you've done 16–19, it'll make sense in context

## 21. Cluster autoscaler, watched live (no new files — reused a throwaway manifest)
- `/tmp/autoscaler-demo-new.yaml` — a temporary demo Deployment, applied and deleted, not part of either repo

## 22. This repo's chart copy
- [ ] `charts/Chart.yaml`, `charts/values.yaml`, `charts/templates/*` — copy of steps 16–17's chart, flattened directly under `charts/` in *this* repo for reference
- [ ] `charts/values/*.yaml` — copy of step 18
