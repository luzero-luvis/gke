#!/usr/bin/env python3
"""Check effective nested resource settings in terraform test -json -verbose output."""
import json
from pathlib import Path
import sys


def check(plan, name):
    changes = [r for r in plan["resource_changes"] if r["mode"] == "managed"]

    def resources(kind):
        return [r["change"]["after"] for r in changes if r["type"] == kind]

    def one(kind):
        matches = resources(kind)
        assert len(matches) == 1, f"{name}: expected one {kind}, found {len(matches)}"
        return matches[0]

    cluster = one("google_container_cluster")
    assert cluster["deletion_protection"] is True
    assert cluster["datapath_provider"] == "ADVANCED_DATAPATH"
    assert cluster["private_cluster_config"][0]["enable_private_nodes"] is True
    endpoints = cluster["control_plane_endpoints_config"][0]
    assert endpoints["ip_endpoints_config"][0]["enabled"] is False
    assert endpoints["dns_endpoint_config"][0]["allow_external_traffic"] is True
    assert endpoints["dns_endpoint_config"][0]["enable_k8s_tokens_via_dns"] is False
    assert cluster["database_encryption"][0]["state"] == "ENCRYPTED"
    assert cluster["workload_identity_config"][0]["workload_pool"].endswith(".svc.id.goog")
    pool = one("google_container_node_pool")
    assert pool["autoscaling"][0]["min_node_count"] == 1
    assert pool["management"][0] == {"auto_repair": True, "auto_upgrade": True}
    assert pool["upgrade_settings"][0]["max_unavailable"] == 0
    node = pool["node_config"][0]
    assert node["shielded_instance_config"][0]["enable_secure_boot"] is True
    assert node["workload_metadata_config"][0]["mode"] == "GKE_METADATA"
    assert node["kubelet_config"][0]["insecure_kubelet_readonly_port_enabled"] == "FALSE"
    assert node["kubelet_config"][0]["cpu_manager_policy"] == "none"
    assert not node["spot"] and not node["preemptible"]
    assert not resources("google_service_account_key")
    assert {r["role"] for r in resources("google_project_iam_member")} <= {
        "roles/container.defaultNodeServiceAccount", "roles/container.clusterViewer"
    }
    assert one("google_compute_subnetwork")["private_ip_google_access"] is True
    assert one("google_compute_router_nat")["source_subnetwork_ip_ranges_to_nat"] == "LIST_OF_SUBNETWORKS"
    backup = one("google_gke_backup_backup_plan")
    assert backup["backup_config"][0]["include_volume_data"] is True
    assert backup["backup_config"][0]["include_secrets"] is True
    assert backup["retention_policy"][0]["backup_delete_lock_days"] >= 7
    policy = one("google_binary_authorization_policy")["default_admission_rule"][0]
    if name == "private_foundation":
        assert policy["enforcement_mode"] == "DRYRUN_AUDIT_LOG_ONLY"
        assert not resources("google_compute_global_address")
    else:
        assert policy["enforcement_mode"] == "ENFORCED_BLOCK_AND_AUDIT_LOG"
        assert policy["evaluation_mode"] == "REQUIRE_ATTESTATION"
        armor = one("google_compute_security_policy")
        assert any(r["action"] == "throttle" for r in armor["rule"])
        assert any(r["action"] == "deny(403)" and not r["preview"] for r in armor["rule"])
        assert one("google_compute_ssl_policy")["min_tls_version"] == "TLS_1_2"
        grant = one("google_secret_manager_secret_iam_member")
        assert grant["member"].endswith("/subject/ns/apps/sa/app")
        assert grant["secret_id"] == "app-password"


def main(path):
    seen = set()
    summary = None
    for line in Path(path).read_text().splitlines():
        event = json.loads(line)
        if event["type"] == "test_summary":
            summary = event["test_summary"]
        name = event.get("@testrun")
        if event["type"] == "test_plan" and name in {"private_foundation", "public_foundation"}:
            check(event["test_plan"], name)
            seen.add(name)
    assert len(seen) == 2, "Both private and public plans must be checked."
    assert summary and summary["failed"] == 0, "Terraform tests must all pass."
    print("Effective resource security checks passed for private and public Terraform plans.")


if __name__ == "__main__":
    main(sys.argv[1])
