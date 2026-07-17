#!/usr/bin/env python3
"""Black-box tests for the canonical fleet lifecycle command."""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
COMMAND = Path(
    os.environ.get("FLEET_LIFECYCLE_COMMAND", REPO_ROOT / "scripts/fleet-lifecycle.py")
)


class FleetLifecycleCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.shell = shutil.which("bash")
        if self.shell is None:
            self.fail("bash is required to exercise the lifecycle command")
        (self.root / "scripts").mkdir()
        (self.root / "hosts.nix").write_text("{}\n", encoding="utf-8")
        self.command_log = self.root / "commands.log"
        self.evidence = self.root / "evidence.json"

        self.write_executable(
            self.root / "scripts/check.sh",
            f"#!{self.shell}\n"
            "printf 'scripts/check.sh\\n' >> \"$FLEET_TEST_COMMAND_LOG\"\n",
        )
        self.write_executable(
            self.bin_dir / "nix",
            f"#!{self.shell}\n"
            "set -eu\n"
            "printf 'nix %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n"
            "if [[ \"$*\" == eval\\ --json\\ --file* ]]; then\n"
            "  printf '%s\\n' '{\"gateway-vm\":{\"tags\":[\"gateway\",\"exposure-consumer\"]},\"gateway2-vm\":{\"tags\":[\"gateway\",\"exposure-consumer\"]},\"monitoring-vm\":{\"tags\":[\"monitoring\",\"exposure-consumer\"]},\"productivity-vm\":{\"tags\":[\"productivity\",\"exposure-consumer\"]},\"testbed-vm\":{\"tags\":[\"testbed\",\"exposure-consumer\"]}}'\n"
            "  exit 0\n"
            "fi\n"
            "exit 64\n",
        )
        self.write_executable(
            self.bin_dir / "colmena",
            f"#!{self.shell}\n"
            "printf 'colmena %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n",
        )

    @staticmethod
    def write_executable(path: Path, contents: str) -> None:
        path.write_text(contents, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_command(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ | {
            "FLEET_TEST_COMMAND_LOG": str(self.command_log),
            "PATH": f"{self.bin_dir}:{Path(self.shell).parent}",
        }
        return subprocess.run(
            [
                sys.executable,
                str(COMMAND),
                *arguments,
                "--repo-root",
                str(self.root),
                "--evidence",
                str(self.evidence),
            ],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def read_evidence(self) -> dict[str, object]:
        return json.loads(self.evidence.read_text(encoding="utf-8"))

    def test_validate_stateless_change_discovers_scope_and_runs_safe_gates(self) -> None:
        result = self.run_command(
            "validate",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--consumer-impact",
            "generated",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        json.loads(result.stdout)
        report = self.read_evidence()
        self.assertEqual(report["outcome"], "complete")
        self.assertFalse(report["mutationAllowed"])
        self.assertEqual(
            report["scope"],
            {
                "affectedHosts": [
                    "testbed-vm",
                    "gateway-vm",
                    "gateway2-vm",
                    "monitoring-vm",
                    "productivity-vm",
                ],
                "consumerHosts": [
                    "gateway-vm",
                    "gateway2-vm",
                    "monitoring-vm",
                    "productivity-vm",
                ],
                "consumerImpact": "generated",
                "consumerReason": "consumer impact was explicitly selected by the operator",
                "runtimeHost": "testbed-vm",
            },
        )
        gates = {gate["id"]: gate for gate in report["gates"]}
        self.assertEqual(gates["scope-discovery"]["status"], "passed")
        self.assertEqual(gates["static-validation"]["status"], "passed")
        self.assertEqual(gates["pre-change-backup"]["status"], "not_applicable")
        self.assertTrue(gates["pre-change-backup"]["reason"])
        self.assertEqual(gates["guarded-deployment"]["status"], "not_applicable")
        self.assertTrue(gates["guarded-deployment"]["reason"])

        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        self.assertIn("scripts/check.sh", commands)
        for host in report["scope"]["affectedHosts"]:
            self.assertIn(f"colmena build --on {host}", commands)
            self.assertIn(f"colmena apply --on {host} dry-activate", commands)
        self.assertFalse(any(" switch" in command for command in commands))

    def test_plan_reports_required_gates_not_run_and_is_incomplete(self) -> None:
        result = self.run_command(
            "plan",
            "--action",
            "addition",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--consumer-impact",
            "generated",
        )

        self.assertNotEqual(result.returncode, 0)
        report = self.read_evidence()
        self.assertEqual(report["outcome"], "incomplete")
        required_not_run = [
            gate
            for gate in report["gates"]
            if gate["required"] and gate["status"] == "not_run"
        ]
        self.assertTrue(required_not_run)
        self.assertTrue(all(gate["reason"] for gate in required_not_run))
        self.assertFalse(any("colmena" in line for line in self.command_log.read_text().splitlines()))

    def test_edit_auto_discovers_generated_consumers_from_changed_catalog(self) -> None:
        self.write_executable(
            self.bin_dir / "git",
            f"#!{self.shell}\n"
            "printf '%s\\n' ' M modules/testbed/catalog.nix'\n",
        )

        result = self.run_command(
            "plan",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
        )

        self.assertNotEqual(result.returncode, 0)
        scope = self.read_evidence()["scope"]
        self.assertEqual(scope["consumerImpact"], "generated")
        self.assertEqual(
            scope["consumerHosts"],
            ["gateway-vm", "gateway2-vm", "monitoring-vm", "productivity-vm"],
        )

    def test_edit_auto_keeps_host_local_change_on_runtime_owner(self) -> None:
        self.write_executable(self.bin_dir / "git", f"#!{self.shell}\nexit 0\n")

        result = self.run_command(
            "plan",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
        )

        self.assertNotEqual(result.returncode, 0)
        scope = self.read_evidence()["scope"]
        self.assertEqual(scope["consumerImpact"], "host-local")
        self.assertEqual(scope["consumerHosts"], [])
        self.assertEqual(scope["affectedHosts"], ["testbed-vm"])

    def test_failed_required_gate_stops_later_gates_and_is_incomplete(self) -> None:
        self.write_executable(
            self.root / "scripts/check.sh",
            f"#!{self.shell}\n"
            "printf 'scripts/check.sh\\n' >> \"$FLEET_TEST_COMMAND_LOG\"\n"
            "exit 23\n",
        )

        result = self.run_command(
            "validate",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--consumer-impact",
            "generated",
        )

        self.assertNotEqual(result.returncode, 0)
        gates = {gate["id"]: gate for gate in self.read_evidence()["gates"]}
        self.assertEqual(gates["static-validation"]["status"], "failed")
        self.assertEqual(gates["build:testbed-vm"]["status"], "not_run")
        self.assertEqual(gates["dry-activate:testbed-vm"]["status"], "not_run")
        self.assertTrue(gates["build:testbed-vm"]["reason"])

    def test_missing_gate_command_is_blocked(self) -> None:
        (self.bin_dir / "colmena").unlink()

        result = self.run_command(
            "validate",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--consumer-impact",
            "generated",
        )

        self.assertNotEqual(result.returncode, 0)
        gates = {gate["id"]: gate for gate in self.read_evidence()["gates"]}
        self.assertEqual(gates["build:testbed-vm"]["status"], "blocked")
        self.assertTrue(gates["build:testbed-vm"]["reason"])

    def test_non_executable_repository_gate_is_blocked_with_evidence(self) -> None:
        (self.root / "scripts/check.sh").chmod(stat.S_IRUSR | stat.S_IWUSR)

        result = self.run_command(
            "validate",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--consumer-impact",
            "host-local",
        )

        self.assertNotEqual(result.returncode, 0)
        json.loads(result.stdout)
        gates = {gate["id"]: gate for gate in self.read_evidence()["gates"]}
        self.assertEqual(gates["static-validation"]["status"], "blocked")
        self.assertTrue(gates["static-validation"]["reason"])

    def test_live_operation_is_not_part_of_the_non_mutating_interface(self) -> None:
        result = self.run_command(
            "deploy",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid choice", result.stderr)
        self.assertFalse(self.command_log.exists())


if __name__ == "__main__":
    unittest.main()
