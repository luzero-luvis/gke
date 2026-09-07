#!/usr/bin/env python3
"""Render reviewable manifests from non-secret Terraform outputs; never deploy."""

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def render(config, image, output, reader_group=None):
    repository = config["repository"]
    if not re.fullmatch(re.escape(repository) + r"/[a-z0-9][a-z0-9/._-]*@sha256:[a-f0-9]{64}", image):
        raise ValueError("Image must be in the Terraform-created repository and pinned with @sha256:<64 lowercase hex characters>.")
    if image.endswith("0" * 64):
        raise ValueError("Replace the placeholder image digest with a real built and scanned image digest.")
    output = Path(output)
    # Refuse to mix new files with stale edge routing from an earlier render.
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("Output directory must be empty; choose a new release directory.")
    values = {"APP_IMAGE": image}
    files = ["foundation.yaml", "application.yaml"]
    edge = config.get("public_app")
    if edge:
        for key in ["hostname", "address_name", "certificate_map", "security_policy", "ssl_policy"]:
            values[key.upper()] = edge[key]
        files += ["edge-policy.yaml", "edge-routing.yaml"]
    rendered = {}
    for name in files:
        content = (ROOT / "workloads" / "templates" / name).read_text()
        for key, value in values.items():
            # JSON-escaped strings are valid quoted YAML scalars.
            content = content.replace('"${' + key + '}"', json.dumps(value))
        if re.search(r"\$\{[^}]+\}", content):
            raise ValueError(f"Unresolved placeholder in {name}")
        rendered[name] = content
    if reader_group:
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", reader_group):
            raise ValueError("Reader group must be a Google Group email configured under the GKE RBAC security group.")
        rendered["reader-rbac.json"] = json.dumps({
            "apiVersion": "rbac.authorization.k8s.io/v1", "kind": "RoleBinding",
            "metadata": {"name": "workload-readers", "namespace": "apps"},
            "roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": "Role", "name": "workload-reader"},
            "subjects": [{"apiGroup": "rbac.authorization.k8s.io", "kind": "Group", "name": reader_group}],
        }, indent=2) + "\n"
    for name, content in rendered.items():
        (output / name).write_text(content)
    return list(rendered)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path, help="terraform output -json workload_config")
    parser.add_argument("--image", required=True, help="Artifact Registry image pinned by digest")
    parser.add_argument("--output", required=True, type=Path, help="Empty destination directory")
    parser.add_argument("--reader-group", help="Optional read-only Google Group RoleBinding")
    args = parser.parse_args()
    try:
        files = render(json.loads(args.config.read_text()), args.image, args.output, args.reader_group)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Render failed: {error}\n")
    print(f"Rendered {len(files)} files in {args.output}. Review and deploy in the order documented in README.md.")


if __name__ == "__main__":
    main()
