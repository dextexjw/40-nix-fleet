#!/usr/bin/env python3
"""Reject evaluated OCI deployment images that lack immutable digests."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


DIGEST_PIN = re.compile(r"@sha256:[0-9a-f]{64}$")


def load_object(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evaluated-containers", type=Path, required=True)
    parser.add_argument("--exceptions", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        containers = load_object(arguments.evaluated_containers)
        exceptions = load_object(arguments.exceptions)
        if exceptions.get("schemaVersion") != 1 or not isinstance(
            exceptions.get("exceptions"), list
        ):
            raise ValueError(
                "deployment pin exceptions must use schemaVersion 1 and an exceptions array"
            )
        allowed = set()
        for index, item in enumerate(exceptions["exceptions"]):
            required = ("host", "container", "image", "reason", "owner", "reviewBy")
            if not isinstance(item, dict) or any(
                not isinstance(item.get(key), str) or not item[key].strip()
                for key in required
            ):
                raise ValueError(
                    f"deployment pin exception {index} requires non-empty "
                    f"{', '.join(required)}"
                )
            allowed.add((item["host"], item["container"], item["image"]))
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    violations = []
    for host, host_containers in sorted(containers.items()):
        if not isinstance(host_containers, dict):
            violations.append(f"{host}: evaluated containers must be an object")
            continue
        for container, config in sorted(host_containers.items()):
            image = config.get("image") if isinstance(config, dict) else None
            if not isinstance(image, str) or not DIGEST_PIN.search(image):
                if isinstance(image, str) and (host, container, image) in allowed:
                    continue
                violations.append(f"{host}/{container}: {image!r}")
    if violations:
        print(
            "error: deployment images must be immutable; pin the image by sha256 "
            "digest or add an exact documented exception:",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 1
    print("Evaluated deployment image pins are immutable.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
