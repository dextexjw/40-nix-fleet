#!/usr/bin/env python3
"""Black-box allowed/denied scenarios for the fleet command hook."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / ".codex" / "hooks" / "fleet-command-guard.py"


class FleetCommandGuardTests(unittest.TestCase):
    def check(self, command: str) -> subprocess.CompletedProcess[str]:
        payload = {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command},
            "cwd": str(ROOT),
        }
        return subprocess.run(
            [str(GUARD)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_allowed(self, command: str) -> None:
        result = self.check(command)
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_denied(self, command: str, safe_path: str) -> None:
        result = self.check(command)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(safe_path, result.stderr)

    def test_allows_guarded_deployment_and_diagnostics(self) -> None:
        for command in (
            "colmena apply --on media-vm switch",
            "colmena apply --on=media-vm switch",
            "scripts/media-vm/deploy-media.sh",
            "colmena build --on media-vm",
            "systemctl status jellyfin",
            "sops secrets/secrets.yaml",
            "sops --decrypt secrets/secrets.yaml >/dev/null",
            "scripts/media-vm/restore-media-appdata.sh deadbeef",
            "rm -rf /tmp/fleet-test",
        ):
            with self.subTest(command=command):
                self.assert_allowed(command)

    def test_denies_unscoped_switch(self) -> None:
        self.assert_denied("colmena apply switch", "--on <host>")

    def test_denies_unsafe_secret_commands(self) -> None:
        for command in (
            "cat secrets/secrets.yaml",
            "sed -n 1,20p secrets/secrets.yaml",
            "vim secrets/secrets.yaml",
            "sops --decrypt secrets/secrets.yaml",
            "sops -d secrets/secrets.yaml",
            "sops decrypt secrets/secrets.yaml",
            "sops secrets/secrets.yaml; cat secrets/secrets.yaml",
        ):
            with self.subTest(command=command):
                self.assert_denied(command, "SOPS-aware")

    def test_denies_implicit_or_automatic_restore(self) -> None:
        for command in (
            "restic restore latest --target /",
            "restic -r /repo restore latest --target /tmp/restore",
            "restic -r /repo restore --target /tmp/restore latest",
            "scripts/media-vm/restore-media-appdata.sh",
            "./scripts/media-vm/restore-media-appdata.sh",
            "scripts/gateway2-vm/restore-from-gateway-vm-backup.sh",
        ):
            with self.subTest(command=command):
                self.assert_denied(command, "explicit snapshot")

    def test_denies_destructive_provisioning_and_state_deletion(self) -> None:
        self.assert_denied("nixos-anywhere --flake .#media-vm root@host", "external provisioning")
        self.assert_denied("sudo rm -rf /srv/appsdata", "declarative removal")
        self.assert_denied("rm -r -f /srv/appsdata/app", "declarative removal")
        self.assert_denied(
            "rm -rf --one-file-system /srv/appsdata/app", "declarative removal"
        )


if __name__ == "__main__":
    unittest.main()
