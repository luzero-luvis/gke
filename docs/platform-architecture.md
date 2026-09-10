# Platform Architecture

Everything that's actually running, in one place — one shared Gateway, one
GKE cluster, two app stacks (the `gke` platform repo's own test app and the
`mts-ijp` stack riding on top of it), and every supporting service between
them, down to which secret each pod can read. All names/values below are
real, taken from the live project (`spartan-calling-484711-e5`, cluster
`test-gke`, `asia-south1`) — except the public hostname, which is written
here as `example.com` in place of the actual company domain.

## 1. What happens when a request comes in

Traced for one real example — `GET /ondc/health`. Every other public path
(`/api`, `/api/v1`, `/mobility/v1`, `/wa`, `/`) takes the same hops, just
landing on a different Service, with or without the rewrite step.

```mermaid
flowchart LR
    A[Browser] -->|resolve host| B[Cloud DNS<br/>example-com zone]
    B -->|route to IP| C["Global HTTPS LB<br/>34.49.112.208<br/>Cloud Armor + SSL policy"]
    C -->|terminate TLS| D["Gateway 'app' (ns apps)<br/>no fixed hostname —<br/>shared by every HTTPRoute"]
    D -->|match listener| E["HTTPRoute: /ondc/*<br/>filter: strip '/ondc' → '/'"]
    E -->|forward, rewritten<br/>as /health| F["Service<br/>ondc-adapter:80"]
    F --> G["Pod: ondc-adapter<br/>:5060 /health"]
```

The rewrite step only fires for `ondc-adapter` and `wa-bot` — their own
code expects root-relative routes. `backend` and `mobility-api` skip it
since their code already answers on `/api/*` and `/api/v1`/`/mobility/v1`
natively.

## 2. Cluster autoscaler, the actual timeline

What happened, second by second, when a pod requested more CPU than
either running node had free — the same mechanism that fires on a real
traffic spike.

```mermaid
flowchart LR
    A["Pod: Pending<br/>0/2 nodes available<br/>Insufficient cpu<br/>t+0s"] -->
    B["cluster-autoscaler<br/>TriggeredScaleUp<br/>instanceGroup 1→2<br/>t+0s"] -->
    C["GCE instance boots<br/>e2-standard-2, COS image<br/>kubelet joins cluster<br/>t+~40s"] -->
    D["Node: Ready<br/>gke-...-sccb<br/>joins asia-south1-c<br/>t+58s"] -->
    E["Pod: Running<br/>scheduled, 1/1<br/>t+59s"]
```

**Boot to `Ready` in 58 seconds** — fast because GKE nodes use pre-baked
images and `e2` boots quickly; a custom-image or heavier-bootstrap node
pool is more commonly 2–4 minutes. Node pool ceiling is
`max_nodes_per_zone = 2`, so this could repeat once more per zone before
the autoscaler gives up and leaves pods `Pending`.

## 3. How a service gets its password — without anyone writing it down

**In plain terms:** each of our 6 services that needs a password (an API
key, a signing secret, etc.) proves *who it is* to Google Cloud, the same
way an employee badge proves who you are at a locked door — no password
is ever typed into a config file, emailed, or stored on disk anywhere.
Google checks the badge, confirms which service it belongs to, and hands
over **only that one service's** password, locked in a vault the rest of
the system can't open. If someone got into the `wa-bot` service, they
still couldn't read `ondc-adapter`'s password — each badge only opens its
own vault.

```mermaid
flowchart LR
    A["backend service<br/>shows its identity badge"] -->
    B["Google Cloud<br/>checks the badge,<br/>no password needed to check it"] -->
    C["Vault<br/>(Secret Manager)<br/>unlocks ONE password —<br/>backend's own, nothing else"] -->
    D["backend service<br/>uses the password<br/>to talk to the next service"]
```

That's the whole idea. Below is the same thing again, with the real
component names, for whoever's building or debugging this.

<details>
<summary>Technical version — the actual chain of systems involved</summary>

Traced for `backend` reading `OTP_PLANNER_SECRET`. Same chain for all 6
services that read secrets — only the identity/secret names change. The
twist this cluster forced: the "sync to a real Kubernetes Secret" feature
doesn't run here, so the last step reads the mounted file directly
instead of an env var Kubernetes would otherwise inject.

```mermaid
sequenceDiagram
    participant Pod as Pod (KSA: backend)
    participant Meta as GKE metadata server
    participant WIF as Workload Identity Federation
    participant GSA as GSA: backend-secrets-reader
    participant SM as Secret Manager<br/>mts-ijp-otp-planner-secret
    participant CSI as Secrets Store CSI driver
    participant App as Flask process

    Pod->>Meta: request a token
    Meta->>WIF: exchange via PROJECT.svc.id.goog[mts-ijp/backend]
    WIF->>GSA: federated identity, no key file
    GSA->>SM: secretAccessor (this GSA only)
    SM->>CSI: mount as file
    CSI->>Pod: /mnt/secrets-store/OTP_PLANNER_SECRET
    Pod->>App: wrapper: export $(cat ...) then exec python app.py
    App->>App: sign JWT with real secret, call gateway → 200
```

</details>

Least privilege, end to end: six GSAs exist, one per service, and each
can read *only* the secret(s) that one service needs — `wa-bot`'s GSA
cannot touch `ondc-adapter`'s secret, and vice versa. Getting this wrong
(the Dockerfile's placeholder secret instead of this real one) was
exactly the `backend` → `{"otp": "down"}` bug.

## 4. Every component, nothing skipped

```mermaid
flowchart TB
    subgraph Internet
        Browser[Browser / client]
        CF[Cloudflare DNS<br/>example.com]
    end

    subgraph GCP["GCP Project: spartan-calling-484711-e5"]
        subgraph Edge["Edge (project-level, outside the VPC)"]
            DNS["Cloud DNS<br/>example-com (public)<br/>test-gke-googleapis, cluster.local (private)"]
            IP["Static IP: 34.49.112.208"]
            CM["Certificate Manager<br/>cert map + managed cert per hostname"]
            Armor["Cloud Armor: test-gke-armor (audit-only)"]
            SSL["SSL Policy: TLS 1.2, MODERN"]
        end

        subgraph VPC["VPC: test-gke-vpc"]
            Subnet["Subnet 10.64.0.0/20 nodes<br/>10.65.0.0/16 pods · 10.66.0.0/20 services"]
            NAT["Cloud Router + Cloud NAT<br/>outbound only, no public node IPs"]

            subgraph Cluster["GKE Cluster: test-gke (regional, private nodes)"]
                GW["Gateway 'app' (ns apps)<br/>shared IP/cert, no fixed hostname"]
                AS["Cluster Autoscaler: max 2 nodes/zone"]
                CSID["Secrets Store CSI driver + GKE provider<br/>(daemonset, both nodes)"]
                Backup["Managed Prometheus · Backup for GKE<br/>(6h → asia-south2)"]

                subgraph ZoneB["asia-south1-b"]
                    PB_apps["ns apps: (Gateway objects only)"]
                    PB_mts["ns mts-ijp: frontend, backend, otp"]
                end
                subgraph ZoneC["asia-south1-c"]
                    PC_mts["ns mts-ijp: gateway, mobility-api,<br/>ondc-adapter, wa-bot"]
                    Disks["disks: otp-data 5Gi, ondc-adapter 2Gi"]
                end
            end
        end

        subgraph Proj["Project-level services (outside the VPC)"]
            IAM["IAM & Workload Identity<br/>6 GSAs, one per secret-reading service"]
            SecMgr["Secret Manager<br/>7 secrets"]
            KMS["Cloud KMS: 1 key ring, 1 key<br/>encrypts K8s Secrets at rest"]
            AR["Artifact Registry: test-gke-apps<br/>8 images built this session"]
            GCS["Cloud Storage<br/>gke-bucket-sirpi (TF state)<br/>...-mts-ijp-gtfs (GTFS/OSM)"]
            Mon["Cloud Monitoring: 6 alert policies<br/>(no notification channel yet)"]
            BinAuth["Binary Authorization: audit-only, no attestors"]
        end
    end

    Browser --> CF --> DNS --> IP --> GW
    GW --> ZoneB
    GW --> ZoneC
```

## 5. Reference — every secret, every grant

| KSA | GSA | Can read | Used by |
|---|---|---|---|
| `otp` | `otp-gcs-reader` | GTFS bucket (`storage.objectViewer`) | fetches 4 GTFS/OSM files at startup |
| `gateway` | `gateway-secrets-reader` | `mts-ijp-otp-planner-secret` | verifies JWTs from `backend` |
| `backend` | `backend-secrets-reader` | `mts-ijp-otp-planner-secret` | signs JWTs to call `gateway` |
| `mobility-api` | `mobility-api-secrets-reader` | `mts-ijp-adapter-notify-secret` | authenticates callbacks from `ondc-adapter` |
| `ondc-adapter` | `ondc-adapter-secrets-reader` | `mts-ijp-mobility-api-notify-secret` | authenticates its own notify calls |
| `wa-bot` | `wa-bot-secrets-reader` | `whatsapp-token`, `wa-verify-token`, `phone-number-id`, `openrouter-api-key` | WhatsApp Graph API + LLM calls |
| `frontend` | *(none)* | — | no secrets needed |

## Public routes → backend

| Path | → Service | Rewrite |
|---|---|---|
| `/` | `frontend` | — |
| `/api` | `backend` | — |
| `/api/v1` | `mobility-api` | — |
| `/mobility/v1` | `mobility-api` | — |
| `/ondc` | `ondc-adapter` | strip → `/` |
| `/wa` | `wa-bot` | strip → `/` |

## Images in Artifact Registry (`test-gke-apps`)

| Image | Note |
|---|---|
| `backend` | Flask |
| `gateway` | rebuilt once — connection-close fix |
| `mobility-api` | FastAPI + `uv` |
| `ondc-adapter` | FastAPI, ONDC BAP |
| `frontend` | Node server, not nginx |
| `wa-bot` | Node/Express |
| `ondc-workbench-simulator` | built, not deployed |

---

See `docs/mts-ijp-deployment.md` and `docs/deployment-log.md` for the
narrative behind each piece, and `docs/learning-roadmap.md` for the
file-by-file build order.
