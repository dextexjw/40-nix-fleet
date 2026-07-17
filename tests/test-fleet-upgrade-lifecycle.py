#!/usr/bin/env python3
"""Focused black-box regressions for stable service upgrade planning."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
COMMAND = Path(
    os.environ.get("FLEET_LIFECYCLE_COMMAND", REPO_ROOT / "scripts/fleet-lifecycle.py")
)


class FleetUpgradeLifecycleTests(unittest.TestCase):
    def test_image_digest_must_match_recorded_immutable_reference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [
                    sys.executable,
                    str(COMMAND),
                    "plan",
                    "--action",
                    "upgrade",
                    "--host",
                    "testbed-vm",
                    "--service-class",
                    "stateful",
                    "--current-version-source",
                    "modules/testbed/services/example.nix: image 1.2.3",
                    "--target-kind",
                    "image",
                    "--target-version",
                    "ghcr.io/example/app:1.3.0@sha256:" + "a" * 64,
                    "--immutable-reference",
                    "sha256:" + "b" * 64,
                    "--migration-requirements",
                    "none",
                    "--dependency-compatibility",
                    "compatible",
                    "--downgrade-support",
                    "supported",
                    "--intermediate-versions",
                    "none",
                    "--configuration-rollback",
                    "previous generation",
                    "--data-rollback",
                    "explicit snapshot restore",
                    "--repo-root",
                    directory,
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("immutable evidence", result.stderr)


if __name__ == "__main__":
    unittest.main()
