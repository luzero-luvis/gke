# mts-ijp

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Mumbai transit trip planner — OTP routing, JWT gateway, Flask API, React SPA and WhatsApp bot

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| luzero-luvis | <jostonluvis@gamil.com> | <https://github.com/luzero-luvis> |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalPorts | list | `[]` | Additional container ports |
| affinity | object | `{}` | Affinity rules for pod assignment |
| args | list | `[]` | Container arguments |
| automountServiceAccountToken | bool | `false` | Automatically mount the ServiceAccount token |
| autoscaling.behavior.scaleDown.policies[0].periodSeconds | int | `60` |  |
| autoscaling.behavior.scaleDown.policies[0].type | string | `"Pods"` |  |
| autoscaling.behavior.scaleDown.policies[0].value | int | `1` |  |
| autoscaling.behavior.scaleDown.stabilizationWindowSeconds | int | `300` |  |
| autoscaling.behavior.scaleUp.policies[0].periodSeconds | int | `15` |  |
| autoscaling.behavior.scaleUp.policies[0].type | string | `"Percent"` |  |
| autoscaling.behavior.scaleUp.policies[0].value | int | `100` |  |
| autoscaling.behavior.scaleUp.policies[1].periodSeconds | int | `15` |  |
| autoscaling.behavior.scaleUp.policies[1].type | string | `"Pods"` |  |
| autoscaling.behavior.scaleUp.policies[1].value | int | `4` |  |
| autoscaling.behavior.scaleUp.selectPolicy | string | `"Max"` |  |
| autoscaling.behavior.scaleUp.stabilizationWindowSeconds | int | `0` |  |
| autoscaling.customMetrics | list | `[]` | Additional autoscaling/v2 MetricSpec entries, appended as-is (e.g. a Pub/Sub queue-depth or requests-per-second target via a metrics adapter/KEDA). Rendered verbatim under `spec.metrics`. |
| autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler for this service |
| autoscaling.maxReplicas | int | `10` | Maximum replica count. Set with real headroom in mind (node/quota capacity) — a runaway scale-up from a metrics blip should hit a wall, not the cluster's ceiling. |
| autoscaling.minReplicas | int | `2` | Minimum replica count. 2+ recommended for any service in the request path — 1 means a scale-up event or node drain can leave zero capacity for the seconds it takes a new pod to become Ready. |
| autoscaling.targetCPUUtilizationPercentage | int | `70` | Target average CPU utilization, as a % of requested CPU. The standard starting point industry-wide; tune down for latency-sensitive services that need to scale before CPU saturates. Empty string disables this metric. |
| autoscaling.targetMemoryUtilizationPercentage | string | `""` | Target average memory utilization, as a % of requested memory. Off by default — memory usage doesn't reliably drop after scale-down the way CPU does, so a memory target can under-react or thrash. Enable only for services that are genuinely memory-bound rather than CPU-bound. Empty string disables this metric. |
| command | list | `[]` | Override container command |
| commonLabels | object | `{}` | Common labels applied to all resources |
| containerPort | int | `8080` | Primary container port |
| deploymentAnnotations | object | `{}` | Annotations for the Deployment resource |
| dnsConfig | object | `{}` | DNS configuration for the pod |
| dnsPolicy | string | `"ClusterFirst"` | DNS policy for the pod |
| env | list | `[]` | Environment variables as key-value pairs (for non-sensitive data) |
| envFrom | list | `[]` | Environment variables from ConfigMap or Secret |
| envFromSecret | object | `{"enabled":false,"secretName":""}` | Environment variables loaded from an existing Secret. This chart never creates the Secret — credentials do not belong in a committed values.yaml. Create it once per namespace:    kubectl -n <ns> create secret generic mts-ijp-secrets \     --from-literal=OTP_PLANNER_SECRET="$(openssl rand -hex 32)" \     --from-literal=OPENROUTER_API_KEY=... \     --from-literal=WHATSAPP_TOKEN=... \     --from-literal=PHONE_NUMBER_ID=... \     --from-literal=VERIFY_TOKEN=... |
| envFromSecret.enabled | bool | `false` | Enable loading environment from the Secret |
| envFromSecret.secretName | string | `""` | Name of the existing Secret |
| fullnameOverride | string | `""` | Override the full name of the chart |
| global | object | `{"imagePullSecrets":[]}` | Global values shared across all releases of this chart |
| global.imagePullSecrets | list | `[]` | Global image pull secrets |
| hostAliases | list | `[]` | Host aliases for the pod |
| hostNetwork | bool | `false` | Enable host network mode |
| hostUsers | bool | `false` | Run the pod in a user namespace (Kubernetes 1.33+). Remove this key on older clusters. |
| httpRoute.backendPolicy.connectionDrainingSec | int | `30` |  |
| httpRoute.backendPolicy.logSampleRate | int | `1` |  |
| httpRoute.backendPolicy.logging | bool | `true` |  |
| httpRoute.backendPolicy.securityPolicy | string | `""` | Cloud Armor security policy name (created by Terraform). Leave empty to skip creating a GCPBackendPolicy for this service. |
| httpRoute.backendPolicy.timeoutSec | int | `30` |  |
| httpRoute.enabled | bool | `false` | Create an HTTPRoute for this service |
| httpRoute.gateway | object | `{"name":"app","namespace":"apps","sectionName":"https"}` | Reference to the pre-existing shared Gateway. Its allowedRoutes must permit this release's namespace (From: All, or a namespace selector) if this service isn't deployed into the Gateway's own namespace. |
| httpRoute.healthCheck.checkIntervalSec | int | `10` |  |
| httpRoute.healthCheck.enabled | bool | `false` | Create a HealthCheckPolicy for this backend |
| httpRoute.healthCheck.healthyThreshold | int | `2` |  |
| httpRoute.healthCheck.path | string | `"/"` |  |
| httpRoute.healthCheck.port | string | `""` | Defaults to containerPort when empty |
| httpRoute.healthCheck.timeoutSec | int | `5` |  |
| httpRoute.healthCheck.unhealthyThreshold | int | `3` |  |
| httpRoute.hostname | string | `""` | Public hostname this service answers on. Required when enabled. |
| httpRoute.paths | list | `[{"rewritePathPrefix":{"enabled":false,"value":""},"type":"PathPrefix","value":"/"}]` | Path matches for the route. One service can answer on several path prefixes on the same hostname (e.g. a service with two independent route groups). Each entry can optionally rewrite its matched prefix before forwarding — for a backend whose own routes are root-relative (e.g. /webhook) but which is exposed under a shared hostname at a sub-path (e.g. /wa). rewritePathPrefix.value: "" strips the matched prefix entirely (e.g. /wa/webhook -> /webhook). |
| image.name | string | `""` (required) | Full image reference including registry, repository, tag, and optional digest |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. `Always` for mutable tags, `IfNotPresent` for digests |
| image.pullSecrets | list | `[]` | Image pull secrets. Can also use global.imagePullSecrets |
| ingress.annotations | object | `{}` | Ingress annotations, e.g. nginx.ingress.kubernetes.io/* rewrite and proxy tuning. |
| ingress.className | string | `"nginx"` | IngressClass name. Leave empty to use the cluster's default IngressClass. |
| ingress.enabled | bool | `false` | Create an Ingress for this service |
| ingress.hostname | string | `""` | Public hostname this service answers on. Required when enabled. |
| ingress.paths | list | `[{"path":"/","pathType":"Prefix"}]` | Path matches for the route. One service can answer on several path prefixes on the same hostname. |
| ingress.tls.clusterIssuer | string | `""` | Name of a cert-manager ClusterIssuer (e.g. letsencrypt-prod). Adds the cert-manager.io/cluster-issuer annotation so cert-manager watches this Ingress and auto-provisions/renews `secretName`. Leave empty to manage the Secret some other way. |
| ingress.tls.enabled | bool | `false` | Enable TLS on this Ingress |
| ingress.tls.secretName | string | `""` | Name of the Secret holding the TLS cert/key. Required when tls.enabled. This chart never creates the Secret itself — either cert-manager provisions it (set `clusterIssuer` below) or it already exists (created manually or synced from elsewhere). |
| initContainers | list | `[]` | Init containers, each run to completion before the main container starts. Full container specs. Used to fetch data into a shared volume — see charts/values/otp.yaml, which pulls the GTFS/OSM artifact from the registry. |
| lifecycle | object | `{"preStop":{"exec":{"command":["/bin/sh","-c","sleep 5"]}}}` | Lifecycle hooks. The preStop sleep lets in-flight requests drain before SIGTERM, once the endpoint has been removed from Service routing. |
| livenessProbe.enabled | bool | `true` | Enable liveness probe |
| livenessProbe.exec.command | list | `[]` |  |
| livenessProbe.failureThreshold | int | `6` |  |
| livenessProbe.grpc.port | int | `8080` |  |
| livenessProbe.grpc.service | string | `""` |  |
| livenessProbe.httpGet.httpHeaders | list | `[]` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| livenessProbe.httpGet.scheme | string | `"HTTP"` |  |
| livenessProbe.initialDelaySeconds | int | `20` |  |
| livenessProbe.periodSeconds | int | `30` |  |
| livenessProbe.successThreshold | int | `1` |  |
| livenessProbe.tcpSocket.port | string | `"http"` |  |
| livenessProbe.timeoutSeconds | int | `5` |  |
| livenessProbe.type | string | `"tcpSocket"` | Probe type: httpGet, exec, tcpSocket, or grpc |
| nameOverride | string | `""` | Override the name of the chart (defaults to the release name) |
| namespaceOverride | string | `""` | Override the target namespace for deployment |
| nodeSelector | object | `{}` | Node selector for pod assignment |
| persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the claim |
| persistence.annotations | object | `{}` | Extra annotations for the PVC |
| persistence.enabled | bool | `false` | Mount a PersistentVolumeClaim into the container |
| persistence.existingClaim | string | `""` | Use an existing claim instead of creating one. Skips PV/PVC creation. |
| persistence.mountPath | string | `"/data"` | Path the volume is mounted at inside the container |
| persistence.readOnly | bool | `false` | Mount the volume read-only |
| persistence.retain | bool | `true` | Keep the PVC on `helm uninstall` |
| persistence.size | string | `"5Gi"` | Requested volume size |
| persistence.storageClass | string | `""` | StorageClass for the PVC:      ""  omit the field — use the cluster's default StorageClass      "-" storageClassName: "" — no class, required to bind a static PV      any that class name, e.g. "longhorn" |
| persistence.subPath | string | `""` | Mount only a sub-directory of the volume |
| persistence.volume.capacity | string | `""` | PV capacity. Defaults to `persistence.size`. Not enforced for local/hostPath volumes — it is only matchmaking metadata. |
| persistence.volume.create | bool | `false` | Create a PersistentVolume alongside the claim |
| persistence.volume.hostPathType | string | `"DirectoryOrCreate"` | hostPath type check (hostPath only) |
| persistence.volume.name | string | `""` | PV name. Defaults to <namespace>-<release>-pv (PVs are cluster-scoped) |
| persistence.volume.nfs | object | `{"path":"","readOnly":false,"server":""}` | NFS settings (type: nfs) |
| persistence.volume.nfs.path | string | `""` | Export path. Falls back to `volume.path` |
| persistence.volume.nfs.readOnly | bool | `false` | Mount the export read-only |
| persistence.volume.nfs.server | string | `""` | NFS server hostname or IP |
| persistence.volume.nodeName | string | `""` | Node holding the data. Required for `local`, and it pins the pod there permanently — fine for the single-replica services, but a node failure becomes an outage rather than a reschedule. |
| persistence.volume.path | string | `"/srv/mts-ijp/data"` | Directory on the node (local/hostPath). Must exist before the pod starts. |
| persistence.volume.reclaimPolicy | string | `"Retain"` | Reclaim policy. `Retain` leaves the PV `Released` after the PVC is deleted; clear spec.claimRef before it will bind again. |
| persistence.volume.type | string | `"local"` | Backing type: `local`, `hostPath`, or `nfs` |
| persistence.volumeName | string | `""` | Bind to a specific PersistentVolume by name. Set automatically when `persistence.volume.create` is true. |
| podAnnotations | object | `{}` | Additional annotations for pods |
| podDisruptionBudget.enabled | bool | `false` | Enable PodDisruptionBudget for high availability |
| podDisruptionBudget.minAvailable | int | `1` | Minimum available pods (use minAvailable OR maxUnavailable, not both) |
| podDisruptionBudget.unhealthyPodEvictionPolicy | string | `"IfHealthyBudget"` | Unhealthy pod eviction policy (Kubernetes 1.26+) |
| podLabels | object | `{}` | Additional labels for pods |
| podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context |
| priorityClassName | string | `""` | Priority class name for pod scheduling |
| readinessProbe.enabled | bool | `true` | Enable readiness probe |
| readinessProbe.exec | object | `{"command":[]}` | Exec probe configuration (when type=exec) |
| readinessProbe.exec.command | list | `[]` | Command to execute for health check |
| readinessProbe.failureThreshold | int | `3` | Consecutive failures for the probe to be considered failed |
| readinessProbe.grpc | object | `{"port":8080,"service":""}` | gRPC probe configuration (when type=grpc) |
| readinessProbe.grpc.port | int | `8080` | gRPC port to probe |
| readinessProbe.grpc.service | string | `""` | gRPC service name |
| readinessProbe.httpGet | object | `{"httpHeaders":[],"path":"/","port":"http","scheme":"HTTP"}` | HTTP GET probe configuration |
| readinessProbe.httpGet.httpHeaders | list | `[]` | HTTP headers to send with the request |
| readinessProbe.httpGet.path | string | `"/"` | HTTP path to probe |
| readinessProbe.httpGet.port | string | `"http"` | HTTP port to probe |
| readinessProbe.httpGet.scheme | string | `"HTTP"` | HTTP scheme (HTTP or HTTPS) |
| readinessProbe.initialDelaySeconds | int | `5` | Seconds after container start before the probe is initiated |
| readinessProbe.periodSeconds | int | `10` | How often (in seconds) to perform the probe |
| readinessProbe.successThreshold | int | `1` | Consecutive successes for the probe to be considered successful |
| readinessProbe.tcpSocket | object | `{"port":"http"}` | TCP socket probe configuration (when type=tcpSocket) |
| readinessProbe.tcpSocket.port | string | `"http"` | TCP port to probe |
| readinessProbe.timeoutSeconds | int | `5` | Seconds after which the probe times out |
| readinessProbe.type | string | `"tcpSocket"` | Probe type: httpGet, exec, tcpSocket, or grpc |
| replicaCount | int | `1` | Number of replicas. Ignored (Deployment.spec.replicas is omitted entirely) when autoscaling.enabled — see that section below. |
| resources | object | `{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | Resource requests and limits (no CPU limit by design to prevent throttling) |
| runtimeClassName | string | `""` | Runtime class name for the pod |
| secretProviderClass.enabled | bool | `false` | Create a SecretProviderClass and mount it (mounting is what triggers the sync into a Kubernetes Secret; the CSI volume itself is unused otherwise, but must be mounted for the driver to run) |
| secretProviderClass.projectNumber | string | `""` | Numeric GCP project number (not the project ID) holding the secrets |
| secretProviderClass.secretName | string | `""` | Name of the synced Kubernetes Secret. envFromSecret.secretName should usually match this. |
| secretProviderClass.secrets | list | `[]` | Secret Manager entries to sync. `key` becomes the env var name once loaded via envFromSecret; `secretId` is the Secret Manager secret ID (short name, not the full resource path); `version` defaults to latest. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Container-level security context |
| securityContext.readOnlyRootFilesystem | bool | `true` | Read-only root filesystem (recommended) |
| service.additionalPorts | list | `[]` | Additional service ports (for multi-port services) |
| service.annotations | object | `{}` | Service annotations |
| service.enabled | bool | `true` | Create the Service |
| service.labels | object | `{}` | Service labels |
| service.loadBalancerSourceRanges | list | `[]` | Load balancer source ranges (when type=LoadBalancer) |
| service.port | int | `80` | Service port (external port exposed by the service) |
| service.protocol | string | `"TCP"` | Service protocol |
| service.sessionAffinity | string | `"None"` | Session affinity for client IP stickiness |
| service.targetPort | string | `"http"` | Target port (container port that the service routes to) |
| service.type | string | `"ClusterIP"` | Kubernetes service type |
| serviceAccountName | string | `""` | Name of an existing ServiceAccount to run as. Empty uses `default`. |
| shareProcessNamespace | bool | `false` | Share process namespace between containers |
| startupProbe.enabled | bool | `false` | Enable startup probe for slow-starting containers |
| startupProbe.exec.command | list | `[]` |  |
| startupProbe.failureThreshold | int | `30` |  |
| startupProbe.grpc.port | int | `8080` |  |
| startupProbe.grpc.service | string | `""` |  |
| startupProbe.httpGet.httpHeaders | list | `[]` |  |
| startupProbe.httpGet.path | string | `"/"` |  |
| startupProbe.httpGet.port | string | `"http"` |  |
| startupProbe.httpGet.scheme | string | `"HTTP"` |  |
| startupProbe.initialDelaySeconds | int | `0` |  |
| startupProbe.periodSeconds | int | `10` |  |
| startupProbe.successThreshold | int | `1` |  |
| startupProbe.tcpSocket.port | string | `"http"` |  |
| startupProbe.timeoutSeconds | int | `5` |  |
| startupProbe.type | string | `"tcpSocket"` | Probe type: httpGet, exec, tcpSocket, or grpc |
| strategy | object | `{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}` | Deployment update strategy |
| terminationGracePeriodSeconds | int | `30` | Termination grace period in seconds |
| tmpVolume | object | `{"enabled":true,"sizeLimit":"512Mi"}` | Temporary volume (mounted at /tmp when readOnlyRootFilesystem=true) |
| tmpVolume.enabled | bool | `true` | Enable the temporary volume |
| tmpVolume.sizeLimit | string | `"512Mi"` | Size limit for the temporary volume |
| tolerations | list | `[]` | Tolerations for pod assignment |
| topologySpreadConstraints | object | `{"constraints":[{"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"ScheduleAnyway"}],"enabled":false}` | Topology spread constraints for high availability |
| topologySpreadConstraints.constraints | list | `[{"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"ScheduleAnyway"}]` | Constraint rules. labelSelector is populated by the chart. |
| topologySpreadConstraints.enabled | bool | `false` | Enable topology spread constraints |
| volumeMounts | list | `[]` | Additional volume mounts for the container |
| volumes | list | `[]` | Additional volumes for the pod |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
