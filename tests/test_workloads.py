import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("render", ROOT / "scripts/render-workloads.py")
RENDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RENDER)
REPOSITORY = "asia-south1-docker.pkg.dev/gke-test/production-gke-apps"
IMAGE = REPOSITORY + "/api@sha256:" + "a" * 64


class WorkloadTests(unittest.TestCase):
    def render(self, edge=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        destination = Path(temporary.name)
        config = {"repository": REPOSITORY, "gateway": None}
        if edge:
            config["gateway"] = {
                "address_name": "production-gke-https", "certificate_map": "production-gke-https",
                "ssl_policy": "production-gke-tls",
                "apps": {"app": {"hostname": "api.example.com", "security_policy": "production-gke-armor"}},
            }
        RENDER.render(config, IMAGE, destination, reader_group="readers@example.com")
        resources = []
        for path in destination.iterdir():
            resources.extend(yaml.safe_load_all(path.read_text()))
        return destination, {(r["kind"], r["metadata"]["name"]): r for r in resources}

    def test_private_render_has_no_public_entry(self):
        _, resources = self.render()
        self.assertFalse(any(k[0] in ["Gateway", "HTTPRoute", "GCPBackendPolicy"] for k in resources))
        service = resources["Service", "app"]
        self.assertEqual(service["spec"]["type"], "ClusterIP")
        policy = resources["NetworkPolicy", "default-deny"]["spec"]
        self.assertEqual(set(policy["policyTypes"]), {"Ingress", "Egress"})
        self.assertNotIn("ingress", policy)
        self.assertNotIn("egress", policy)

    def test_hpa_peak_and_rollout_fit_quota(self):
        _, resources = self.render()
        deploy = resources["Deployment", "app"]["spec"]
        container = deploy["template"]["spec"]["containers"][0]
        peak = resources["HorizontalPodAutoscaler", "app"]["spec"]["maxReplicas"] + deploy["strategy"]["rollingUpdate"]["maxSurge"]
        quota = resources["ResourceQuota", "apps"]["spec"]["hard"]
        self.assertLessEqual(peak * int(container["resources"]["limits"]["cpu"]), int(quota["limits.cpu"]))
        self.assertLessEqual(peak, int(quota["pods"]))
        self.assertEqual(resources["VerticalPodAutoscaler", "app"]["spec"]["updatePolicy"]["updateMode"], "Off")

    def test_public_route_has_tls_and_scoped_backend_policy(self):
        _, resources = self.render(edge=True)
        gateway = resources["Gateway", "app"]
        self.assertEqual([p["port"] for p in gateway["spec"]["listeners"]], [443])
        self.assertIn("networking.gke.io/certmap", gateway["metadata"]["annotations"])
        route = resources["HTTPRoute", "app"]["spec"]
        self.assertEqual(route["hostnames"], ["api.example.com"])
        self.assertEqual(route["rules"][0]["backendRefs"][0]["name"], "app")
        policy = resources["GCPBackendPolicy", "app"]["spec"]
        self.assertEqual(policy["targetRef"]["name"], "app")
        self.assertEqual(policy["default"]["securityPolicy"], "production-gke-armor")
        ingress = resources["NetworkPolicy", "allow-google-load-balancer"]["spec"]["ingress"]
        self.assertEqual({v["ipBlock"]["cidr"] for v in ingress[0]["from"]}, {"35.191.0.0/16", "130.211.0.0/22"})

    def test_restricted_workload_and_keyless_identity(self):
        _, resources = self.render()
        pod = resources["Deployment", "app"]["spec"]["template"]["spec"]
        self.assertFalse(pod["automountServiceAccountToken"])
        self.assertEqual(pod["serviceAccountName"], "app")
        self.assertTrue(pod["securityContext"]["runAsNonRoot"])
        container = pod["containers"][0]
        self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])
        self.assertFalse(container["securityContext"]["allowPrivilegeEscalation"])
        rules = resources["Role", "workload-reader"]["rules"]
        self.assertFalse(any("secrets" in r["resources"] or "*" in r["verbs"] for r in rules))
        egress = resources["NetworkPolicy", "app-google-api-access"]["spec"]["egress"]
        self.assertEqual({p["port"] for p in egress[0]["ports"]}, {80, 8080})
        self.assertNotIn("0.0.0.0/0", json.dumps(egress))

    def test_reject_mutable_wrong_registry_and_placeholder_images(self):
        for image in [REPOSITORY + "/api:latest", "wrong.registry/api@sha256:" + "a" * 64, REPOSITORY + "/api@sha256:" + "0" * 64]:
            with self.subTest(image=image), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    RENDER.render({"repository": REPOSITORY}, image, directory)

    def test_multi_app_shares_gateway_but_keeps_distinct_route(self):
        config = {
            "repository": REPOSITORY,
            "gateway": {
                "address_name": "production-gke-https", "certificate_map": "production-gke-https",
                "ssl_policy": "production-gke-tls",
                "apps": {
                    "app": {"hostname": "api.example.com", "security_policy": "production-gke-armor"},
                    "docs": {"hostname": "docs.example.com", "security_policy": "production-gke-docs-armor"},
                },
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            RENDER.render(config, IMAGE, directory, app="docs")
            resources = {}
            for path in Path(directory).iterdir():
                for r in yaml.safe_load_all(path.read_text()):
                    resources[(r["kind"], r["metadata"]["name"])] = r
        # Gateway itself carries no per-app hostname; only the route does.
        self.assertNotIn("hostname", resources["Gateway", "app"]["spec"]["listeners"][0])
        self.assertEqual(resources["HTTPRoute", "app"]["spec"]["hostnames"], ["docs.example.com"])
        self.assertEqual(resources["GCPBackendPolicy", "app"]["spec"]["default"]["securityPolicy"], "production-gke-docs-armor")

    def test_reject_reuse_to_prevent_stale_public_routes(self):
        directory, _ = self.render(edge=True)
        with self.assertRaises(ValueError):
            RENDER.render({"repository": REPOSITORY}, IMAGE, directory)


if __name__ == "__main__":
    unittest.main()
