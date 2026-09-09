# mts-ijp on GKE: Deployment Log

What was done to get the `mts-ijp` (Mumbai transit trip planner) stack —
a separate repo (`~/sirpi-in/mts-ijp`, `feat/helm-chart` branch) — running
on the same GKE cluster (`test-gke`, project `spartan-calling-484711-e5`)
that `luvis-in/gke`'s Terraform builds. Every resource name below is real
and currently live. The Helm chart itself is copied into this repo at
`charts/` for reference; the source of truth for chart development is
still the `mts-ijp` repo.

## What's live

| | |
|---|---|
| Namespace | `mts-ijp` (restricted Pod Security Standard) |
| Public hostname | `gke.luzero.online` — shared with `luvis-in/gke`'s own app via path-based routing, same Gateway/IP/cert |
| Services | `otp`, `gateway`, `backend`, `mobility-api`, `ondc-adapter`, `frontend`, `wa-bot` — all `1/1 Running` |
| GCS bucket | `gs://spartan-calling-484711-e5-mts-ijp-gtfs` (`asia-south1`) |
| Artifact Registry | reused `test-gke-apps` repo, images tagged by git short SHA (`aec94b0`) |
| Secrets | 7, in Secret Manager, per-service least-privilege access |

## 1. Shared Gateway changes (in `luvis-in/gke`)

`workloads/templates/gateway.yaml`'s listener only allowed `HTTPRoute`s
from its own namespace (`apps`). Widened to accept routes from any
namespace so `mts-ijp` can attach without needing its own Gateway/IP/cert:

```diff
   listeners:
     - name: https
       protocol: HTTPS
       port: 443
       allowedRoutes:
-        namespaces: {from: Same}
+        namespaces: {from: All}
```

Re-applied directly (`kubectl apply --server-side`) since it's a live
cluster object, not (yet) re-rendered through Terraform's
`workload_config` output.

The old smoke-test app's `Deployment`/`Service`/`HTTPRoute`/`NetworkPolicy`
in `apps` (from earlier verification work) were deleted to free the `/`
path on `gke.luzero.online` for `mts-ijp`'s `frontend`.

## 2. Namespace

```
kubectl create namespace mts-ijp
kubectl label --overwrite namespace mts-ijp \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

No `ResourceQuota`/`NetworkPolicy` created yet for this namespace (unlike
`apps`'s `foundation.yaml`) — worth adding before this is treated as
production, since egress needs vary a lot per service here (`wa-bot` needs
the public internet for WhatsApp Graph API + OpenRouter; `ondc-adapter`/
`mobility-api` need it for the real ONDC network).

## 3. GCS bucket for OTP's GTFS/OSM data

Files (`best_gtfs.zip`, `mumbai-metro-gtfs.zip`, `shared-auto-gtfs.zip`,
`mumbai.osm.pbf`) were sitting locally in the `mts-ijp` repo root, not in
GCS or the image. `docker-compose.yml` mounted them individually at exact
paths under `/var/opentripplanner`, so OTP's chart values preserve that
exact layout.

```
gcloud storage buckets create gs://spartan-calling-484711-e5-mts-ijp-gtfs \
  --project=spartan-calling-484711-e5 --location=asia-south1 \
  --uniform-bucket-level-access
gcloud storage cp best_gtfs.zip mumbai-metro-gtfs.zip \
  shared-auto-gtfs.zip mumbai.osm.pbf \
  gs://spartan-calling-484711-e5-mts-ijp-gtfs/
```

## 4. Secrets pushed to Secret Manager

Real secret values were read directly from the repo's local `.env` and
piped straight into `gcloud secrets create`/`versions add` — never printed
to the terminal or this conversation.

| Secret Manager ID | Source `.env` key | Used by |
|---|---|---|
| `mts-ijp-otp-planner-secret` | `OTP_PLANNER_SECRET` | `gateway` (verifies), `backend` (signs — see §9) |
| `mts-ijp-openrouter-api-key` | `OPENROUTER_API_KEY` | `wa-bot` |
| `mts-ijp-whatsapp-token` | `WHATSAPP_TOKEN` | `wa-bot` |
| `mts-ijp-wa-verify-token` | `VERIFY_TOKEN` | `wa-bot` |
| `mts-ijp-whatsapp-phone-number-id` | `PHONE_NUMBER_ID` | `wa-bot` |
| `mts-ijp-mobility-api-notify-secret` | `MOBILITY_API_NOTIFY_SECRET` | `ondc-adapter` |
| `mts-ijp-adapter-notify-secret` | `ADAPTER_NOTIFY_SECRET` | `mobility-api` |

```bash
push_secret() {
  envkey="$1"; secretname="$2"
  value=$(grep -E "^${envkey}=" .env | head -1 | cut -d= -f2-)
  printf '%s' "$value" | gcloud secrets create "$secretname" \
    --project=spartan-calling-484711-e5 --replication-policy=automatic \
    --data-file=-
}
push_secret OTP_PLANNER_SECRET mts-ijp-otp-planner-secret
# ...repeat per row above
```

`PHONE_NUMBER_ID` was initially (wrongly) treated as non-sensitive config;
corrected to its own secret since it's account-specific and shouldn't sit
in a committed values file.

## 5. Workload Identity — one GSA per service, least privilege

Every GSA below can read **only its own service's secret(s)**, nothing
project-wide.

| KSA (namespace `mts-ijp`) | GSA | Access granted |
|---|---|---|
| `otp` | `otp-gcs-reader@spartan-calling-484711-e5.iam.gserviceaccount.com` | `roles/storage.objectViewer` on the GTFS bucket only |
| `gateway` | `gateway-secrets-reader@...` | `secretAccessor` on `mts-ijp-otp-planner-secret` |
| `backend` | `backend-secrets-reader@...` | `secretAccessor` on `mts-ijp-otp-planner-secret` |
| `mobility-api` | `mobility-api-secrets-reader@...` | `secretAccessor` on `mts-ijp-adapter-notify-secret` |
| `ondc-adapter` | `ondc-adapter-secrets-reader@...` | `secretAccessor` on `mts-ijp-mobility-api-notify-secret` |
| `wa-bot` | `wa-bot-secrets-reader@...` | `secretAccessor` on `mts-ijp-openrouter-api-key`, `mts-ijp-whatsapp-token`, `mts-ijp-wa-verify-token`, `mts-ijp-whatsapp-phone-number-id` |
| `frontend` | *(none — default KSA)* | no secrets needed |

Per-service setup pattern (repeat with the right names/secrets):

```bash
gcloud iam service-accounts create <name>-secrets-reader --project=spartan-calling-484711-e5
gcloud secrets add-iam-policy-binding <secret-id> --project=spartan-calling-484711-e5 \
  --member="serviceAccount:<name>-secrets-reader@spartan-calling-484711-e5.iam.gserviceaccount.com" \
  --role=roles/secretmanager.secretAccessor
kubectl -n mts-ijp create serviceaccount <name>
gcloud iam service-accounts add-iam-policy-binding \
  <name>-secrets-reader@spartan-calling-484711-e5.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:spartan-calling-484711-e5.svc.id.goog[mts-ijp/<name>]"
kubectl -n mts-ijp annotate serviceaccount <name> \
  iam.gke.io/gcp-service-account=<name>-secrets-reader@spartan-calling-484711-e5.iam.gserviceaccount.com
```

**Verify grants actually landed** — one `gcloud secrets add-iam-policy-binding`
silently failed the first time round (output was piped to `/dev/null`,
masking the real error) and cost real debugging time. Always confirm with:

```
gcloud secrets get-iam-policy <secret-id> --format="value(bindings.members)"
```

## 6. Building and pushing images

`mts-ijp`'s only existing CI/CD (`​.github/workflows/ci-cd.yml`) deploys to
a **Hetzner VM via `docker compose` over SSH**, building in place —
there's no image-publishing step to reuse. All 7 images were built and
pushed by hand, reusing the `test-gke-apps` Artifact Registry repo:

```bash
REPO=asia-south1-docker.pkg.dev/spartan-calling-484711-e5/test-gke-apps
TAG=$(git rev-parse --short HEAD)   # aec94b0
gcloud auth configure-docker asia-south1-docker.pkg.dev

docker build -t "$REPO/backend:$TAG" -f backend/Dockerfile backend
docker build -t "$REPO/gateway:$TAG" -f backend/gateway.Dockerfile backend
docker build -t "$REPO/mobility-api:$TAG" -f mobility-api/Dockerfile mobility-api
docker build -t "$REPO/ondc-adapter:$TAG" -f adapter/Dockerfile .      # context is repo root
docker build -t "$REPO/ondc-workbench-simulator:$TAG" -f ondc-workbench-simulator/Dockerfile ondc-workbench-simulator
docker build -t "$REPO/frontend:$TAG" -f frontend/Dockerfile frontend
docker build -t "$REPO/wa-bot:$TAG" -f wa-bot/Dockerfile wa-bot
# then docker push each
```

`gateway` was rebuilt a second time after a bug fix (see §11) —
`aec94b0-gwfix1`. Chart values reference images **by digest**
(`@sha256:...`), not by mutable tag, taken from each `docker push` output.
`ondc-workbench-simulator` was built but never deployed (not part of the
5 public-facing services this pass covered).

## 7. Chart additions (generic, reusable — not `mts-ijp`-specific)

Three additions to the existing `charts/mts-ijp` chart, all feature-flagged
so they don't affect services that don't opt in:

- **`templates/httproute.yaml`** + `values.httpRoute` — attaches to the
  pre-existing shared Gateway (never creates one). `paths` is a *list*
  (one release can expose several path prefixes — `mobility-api` needs
  both `/api/v1` and `/mobility/v1`), each with an optional
  `rewritePathPrefix` (strips the matched prefix before forwarding, for
  backends whose own routes are root-relative). Optionally creates a
  `GCPBackendPolicy` (Cloud Armor) and a `HealthCheckPolicy`.
- **`templates/secretproviderclass.yaml`** + `values.secretProviderClass`
  — syncs named Secret Manager entries into the pod via the Secrets Store
  CSI Driver.
- **`templates/deployment.yaml`** changes — auto-mounts the CSI secrets
  volume and adds the `secrets-store.csi.k8s.io/used: "true"` pod label
  when `secretProviderClass.enabled`.

## 8. Routing plan (all under `gke.luzero.online`, one shared LB)

Real routes were checked against each service's actual source code before
committing to a path — not guessed.

| Path | Service | Rewrite | Why |
|---|---|---|---|
| `/` | `frontend` | none | catch-all, lowest precedence |
| `/api` | `backend` | none | Flask routes already `/api/*` |
| `/api/v1` | `mobility-api` | none | more specific than `/api`, wins by Gateway API precedence |
| `/mobility/v1` | `mobility-api` | none | ~13 real endpoints here, not just the internal notify hook |
| `/ondc` | `ondc-adapter` | strip `/ondc` | routes are root-relative (`/health`, `/{action}`); **register the real ONDC callback base URL as `https://gke.luzero.online/ondc`** |
| `/wa` | `wa-bot` | strip `/wa` | routes are root-relative (`/webhook`, `/health`); **WhatsApp webhook URL is `https://gke.luzero.online/wa/webhook`** |
| *(none)* | `gateway` | — | internal only, no public route |

## 9. Bugs found and fixed

All confirmed via live evidence (logs, `gcloud`/`kubectl describe`, direct
`curl`/`exec` tests), not guessed:

1. **`otp` initContainer rejected by `restricted` PSS** — missing
   `allowPrivilegeEscalation: false` / `capabilities.drop: [ALL]`; pod-level
   `securityContext` doesn't cascade to `initContainers` (they're raw specs).
2. **`gcloud` in the initContainer had no writable `$HOME`** — reused the
   chart's existing `tmp` `emptyDir`, set `HOME=/tmp`.
3. **`otp` OOM'd**: `-Xmx1g` too small for the real graph (41k+ trips,
   37k interlined pairs) → bumped to `-Xmx2g`, memory request/limit
   `1536Mi/2Gi` → `2560Mi/3Gi`.
4. **`otp` Deployment deadlocked on rollout** — `RollingUpdate` (default)
   surges a new pod before killing the old one, but the PVC is
   `ReadWriteOnce`; the new pod can't attach while the old one holds it,
   and the old one never gets killed because the new one never becomes
   Ready. Fixed with `strategy: {type: Recreate}`.
5. **`mobility-api` crashed**: `uv run` needs a writable cache dir under
   `readOnlyRootFilesystem: true` → `UV_CACHE_DIR=/tmp/uv-cache`.
6. **Wrong CSI driver name** — `secrets-store.csi.k8s.io` (upstream) vs.
   the actual registered `secrets-store-gke.csi.k8s.io` (GKE's managed
   add-on renames it). Confirmed via `kubectl get csidrivers`.
7. **Wrong provider name** — `gcp` (upstream convention) vs. `gke` (what
   GKE's managed provider actually registers as). No error on `kubectl
   apply`; only surfaced as a mount-time `provider not found` error.
8. **"Sync as Kubernetes Secret" doesn't work on this cluster's add-on at
   all** — the CSI mount itself works, but there's no
   `secrets-store-sync-controller` running (confirmed: no such
   pod/deployment anywhere in the cluster), so `secretObjects` in
   `SecretProviderClass` is silently a no-op. `envFromSecret` against a
   Secret that will never exist just hangs pods in
   `CreateContainerConfigError` forever. **Fix: read the CSI-mounted files
   directly** (`/mnt/secrets-store/<KEY>`) via a `command`/`args` wrapper
   that exports each as an env var before `exec`-ing the real process —
   this is the officially supported pattern for GKE's version of the
   add-on, not a workaround.
9. **One IAM grant silently failed** — `gcloud secrets
   add-iam-policy-binding` piped to `/dev/null 2>&1` in an earlier loop
   masked a real failure for `mts-ijp-openrouter-api-key`; only `wa-bot`
   was affected. Always verify grants with `get-iam-policy` after
   scripting them.
10. **Manually deleting stuck old pods reset Deployment rollout tracking**
    — repeatedly interrupted the controller's view of rollout progress,
    leaving old ReplicaSets stuck at `desired=1` instead of scaling to 0
    automatically. Fixed by directly `kubectl scale replicaset <old> --replicas=0`
    once the new pods were independently confirmed healthy.
11. **GCP Load Balancer marked healthy backends `UNHEALTHY`** — with no
    `HealthCheckPolicy`, GKE Gateway defaults the LB's health check to
    `/`, which 404s on every one of these APIs (their real health paths
    are elsewhere). Confirmed via
    `gcloud compute backend-services get-health <backend>`. Fixed by
    setting `httpRoute.healthCheck` per service to its real path
    (`/api/health`, `/api/v1/health`, `/health`, `/health`). Note: the LB
    health check hits the pod **directly** (bypassing the HTTPRoute path
    rewrite), so for `ondc-adapter`/`wa-bot` the health-check path is the
    real internal path (`/health`), not the externally-rewritten one.
12. **`gateway.py` crashed repeatedly**: `BrokenPipeError` /
    `"Bad request version"` from Python's stdlib `http.server`. Root
    cause: `backend` calls it via `requests`, which pools/reuses HTTP
    connections; `BaseHTTPRequestHandler`'s keep-alive handling doesn't
    reliably survive that. Confirmed by matching the crash's source IP to
    `backend`'s pod IP. **App-code fix** (not infra): force
    `self.close_connection = True` in `gateway.py`'s request handler, so
    no client can reuse a stale socket. Rebuilt/pushed/redeployed
    (`aec94b0-gwfix1`).
13. **`backend` permanently reported `{"otp": "down"}`** even after #12 —
    a *separate* bug: `backend`'s JWT to `gateway` is signed with
    `OTP_PLANNER_SECRET`, but `backend`'s only copy of that value was the
    Dockerfile's baked-in placeholder `"changeme"` (never previously wired
    to Secret Manager) — a mismatched signature, correctly rejected by
    `gateway` with `401`, which `backend`'s own code reports as `"down"`.
    Fixed by giving `backend` the same Workload Identity + Secret Manager
    access as `gateway` (§5), reading the real secret the same
    file-mount way as #8.

## 10. Verification

```bash
# GCP-level backend health (not just pod readiness)
gcloud compute backend-services get-health gkegw1-0u4y-mts-ijp-<service>-80-<hash> --global

# End-to-end route tests
curl https://gke.luzero.online/                 # frontend, 200
curl https://gke.luzero.online/api/health        # backend, {"otp":"up"}
curl https://gke.luzero.online/api/v1/health     # mobility-api, {"status":"ok"}
curl https://gke.luzero.online/ondc/health       # ondc-adapter, rewritten to /health
curl https://gke.luzero.online/wa/webhook        # wa-bot, rewritten to /webhook (403 without valid WhatsApp verify params — expected)
```

All 7 pods `1/1 Running`, 0 restarts; all 4 public API backends `HEALTHY`
at the GCP LB level; `gateway` logs clean (no more crash tracebacks).

## Known gaps / not done in this pass

- No `ResourceQuota`/`NetworkPolicy` for the `mts-ijp` namespace (see §2).
- `ondc-workbench-simulator` image built but not deployed.
- Images are tagged by git short SHA of a **dirty** working tree (`mts-ijp`
  had uncommitted changes at build time) — re-tag/rebuild once that repo's
  changes are actually committed, so the tag means something durable.
- No CI pipeline builds/pushes these images automatically — still a
  manual `docker build && push` per change, unlike the `luvis-in/gke`
  side which at least has `terraform test` in CI.
- `gateway.py`'s fix (#12) lives only in the locally built image; the
  source change in `~/sirpi-in/mts-ijp/backend/gateway.py` is
  **uncommitted** in that repo.
- Cloud Armor (`GCPBackendPolicy.securityPolicy`) not wired up for any
  `mts-ijp` service yet — left empty/skipped for this pass.
