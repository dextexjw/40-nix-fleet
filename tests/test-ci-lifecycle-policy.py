#!/usr/bin/env python3
"""Black-box tests for deterministic, non-live CI lifecycle policy."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "scripts" / "check-deployment-pins.py"


class DeploymentPinPolicyTests(unittest.TestCase):
    def run_policy(
        self, payload: dict, exceptions: dict | None = None
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evaluated = root / "containers.json"
            allowed = root / "exceptions.json"
            evaluated.write_text(json.dumps(payload), encoding="utf-8")
            allowed.write_text(
                json.dumps(exceptions or {"schemaVersion": 1, "exceptions": []}),
                encoding="utf-8",
            )
            return subprocess.run(
                [
                    str(POLICY),
                    "--evaluated-containers",
                    str(evaluated),
                    "--exceptions",
                    str(allowed),
                ],
                text=True,
                capture_output=True,
                check=False,
            )

    def test_accepts_digest_pinned_images(self) -> None:
        result = self.run_policy(
            {"host": {"app": {"image": "registry/app:1.2@sha256:" + "a" * 64}}}
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_floating_or_unpinned_images(self) -> None:
        result = self.run_policy(
            {
                "host": {
                    "one": {"image": "registry/app:latest"},
                    "two": {"image": "registry/db:16"},
                }
            }
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("host/one", result.stderr)
        self.assertIn("host/two", result.stderr)
        self.assertIn("pin the image by sha256 digest", result.stderr)

    def test_allows_only_documented_exact_exceptions(self) -> None:
        exception = {
            "schemaVersion": 1,
            "exceptions": [{
                "host": "host", "container": "app", "image": "registry/app:latest",
                "reason": "upstream test fixture has no immutable publication",
                "owner": "fleet maintainers", "reviewBy": "2099-01-01",
            }],
        }
        result = self.run_policy({"host": {"app": {"image": "registry/app:latest"}}}, exception)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_invalid_or_expired_exception_review_dates(self) -> None:
        for review_by in ("later", "2000-01-01"):
            with self.subTest(review_by=review_by):
                exception = {
                    "schemaVersion": 1,
                    "exceptions": [{
                        "host": "host", "container": "app", "image": "registry/app:latest",
                        "reason": "temporary upstream limitation",
                        "owner": "fleet maintainers", "reviewBy": review_by,
                    }],
                }
                result = self.run_policy(
                    {"host": {"app": {"image": "registry/app:latest"}}}, exception
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("reviewBy", result.stderr)


if __name__ == "__main__":
    unittest.main()
