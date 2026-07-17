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
        self.git = shutil.which("git")
        if self.git is None:
            self.fail("git is required to exercise resumable lifecycle receipts")
        (self.root / "scripts").mkdir()
        (self.root / "hosts.nix").write_text("{}\n", encoding="utf-8")
        self.command_log = self.root / ".git" / "commands.log"
        self.evidence = self.root / ".git" / "evidence.json"
        self.receipts = self.root / ".git" / "fleet-lifecycle-test"

        self.write_executable(
            self.root / "scripts/check.sh",
            f"#!{self.shell}\n"
            "printf 'scripts/check.sh\\n' >> \"$FLEET_TEST_COMMAND_LOG\"\n",
        )
        consumer_surfaces = {
            "gateway-vm": [
                "authentication",
                "dns",
                "firewall",
                "homepage",
                "route",
                "smoke",
                "tls",
            ],
            "gateway2-vm": [
                "authentication",
                "dns",
                "firewall",
                "homepage",
                "route",
                "smoke",
                "tls",
            ],
            "media-vm": [],
            "monitoring-vm": ["dns", "monitoring"],
            "productivity-vm": ["dns"],
            "testbed-vm": ["dns"],
        }
        consumers = {
            host: {
                "consumerSurfaces": surfaces,
                "evidence": {surface: "rendered" for surface in surfaces},
            }
            for host, surfaces in consumer_surfaces.items()
        }
        self.write_executable(
            self.bin_dir / "nix",
            f"#!{self.shell}\n"
            "set -eu\n"
            "printf 'nix %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n"
            "if [[ \"$*\" == 'eval --json .#fleetLifecycleConsumers' ]]; then\n"
            f"  printf '%s\\n' '{json.dumps(consumers, separators=(',', ':'))}'\n"
            "  exit 0\n"
            "fi\n"
            "if [[ \"$*\" == eval\\ --json\\ .#fleetLifecycleConsumers.*.rendered.* ]]; then\n"
            "  if [[ \"${FLEET_TEST_FAIL_CONSUMER_GATE:-}\" == \"${*:3}\" ]]; then printf '%s\\n' false; exit 0; fi\n"
            "  printf '%s\\n' true\n"
            "  exit 0\n"
            "fi\n"
            "exit 64\n",
        )
        self.write_executable(
            self.bin_dir / "colmena",
            f"#!{self.shell}\n"
            "printf 'colmena %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n",
        )
        (self.root / "scripts" / "testbed-vm").mkdir()
        self.write_executable(
            self.root / "scripts" / "testbed-vm" / "upgrade-testbed-vm.sh",
            f"#!{self.shell}\n"
            "set -eu\n"
            "printf 'scripts/testbed-vm/upgrade-testbed-vm.sh %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n"
            "if [[ \"${FLEET_TEST_FAIL_UPGRADE_PHASE:-}\" == \"$*\" ]]; then exit 42; fi\n"
            "printf 'verified phase %s\\n' \"$*\"\n",
        )
        consumer_checks = {
            "gateway-vm": "test-gateway-services.sh",
            "gateway2-vm": "test-gateway2-services.sh",
            "monitoring-vm": "test-monitoring-services.sh",
            "productivity-vm": "test-productivity-services.sh",
        }
        for host, script_name in consumer_checks.items():
            script_dir = self.root / "scripts" / host
            script_dir.mkdir()
            self.write_executable(
                script_dir / script_name,
                f"#!{self.shell}\n"
                f"printf 'scripts/{host}/{script_name}\\n' >> \"$FLEET_TEST_COMMAND_LOG\"\n",
            )

        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(
            ["git", "-C", str(self.root), "config", "user.email", "fleet-test@example.invalid"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(self.root), "config", "user.name", "Fleet Test"],
            check=True,
        )
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(
            ["git", "-C", str(self.root), "commit", "-qm", "test fixture"], check=True
        )

    @staticmethod
    def write_executable(path: Path, contents: str) -> None:
        path.write_text(contents, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_command(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ | {
            "FLEET_TEST_COMMAND_LOG": str(self.command_log),
            "PATH": f"{self.bin_dir}:{Path(self.shell).parent}:{Path(self.git).parent}",
        }
        if hasattr(self, "failed_upgrade_phase"):
            environment["FLEET_TEST_FAIL_UPGRADE_PHASE"] = self.failed_upgrade_phase
        if hasattr(self, "failed_consumer_gate"):
            environment["FLEET_TEST_FAIL_CONSUMER_GATE"] = self.failed_consumer_gate
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
                    "testbed-vm",
                ],
                "consumerSurfaces": {
                    "gateway-vm": [
                        "authentication",
                        "dns",
                        "firewall",
                        "homepage",
                        "route",
                        "smoke",
                        "tls",
                    ],
                    "gateway2-vm": [
                        "authentication",
                        "dns",
                        "firewall",
                        "homepage",
                        "route",
                        "smoke",
                        "tls",
                    ],
                    "media-vm": [],
                    "monitoring-vm": ["dns", "monitoring"],
                    "productivity-vm": ["dns"],
                    "testbed-vm": ["dns"],
                },
                "consumerEvidence": {
                    "gateway-vm": {
                        surface: "rendered"
                        for surface in (
                            "authentication",
                            "dns",
                            "firewall",
                            "homepage",
                            "route",
                            "smoke",
                            "tls",
                        )
                    },
                    "gateway2-vm": {
                        surface: "rendered"
                        for surface in (
                            "authentication",
                            "dns",
                            "firewall",
                            "homepage",
                            "route",
                            "smoke",
                            "tls",
                        )
                    },
                    "media-vm": {},
                    "monitoring-vm": {"dns": "rendered", "monitoring": "rendered"},
                    "productivity-vm": {"dns": "rendered"},
                    "testbed-vm": {"dns": "rendered"},
                },
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
        for host in report["scope"]["consumerHosts"]:
            for surface in report["scope"]["consumerSurfaces"][host]:
                consumer_gate = gates[f"consumer:{host}:{surface}"]
                self.assertEqual(consumer_gate["status"], "passed")
                self.assertEqual(consumer_gate["applicability"], "applicable")

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
            [
                "gateway-vm",
                "gateway2-vm",
                "monitoring-vm",
                "productivity-vm",
                "testbed-vm",
            ],
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

    def test_edit_auto_includes_both_gateways_for_shared_gateway_change(self) -> None:
        self.write_executable(
            self.bin_dir / "git",
            f"#!{self.shell}\n"
            "printf '%s\\n' ' M hosts/gateway-vm/shared.nix'\n",
        )

        result = self.run_command(
            "plan",
            "--action",
            "edit",
            "--host",
            "gateway-vm",
            "--service-class",
            "stateless",
        )

        self.assertNotEqual(result.returncode, 0)
        scope = self.read_evidence()["scope"]
        self.assertEqual(scope["consumerImpact"], "generated")
        self.assertIn("gateway-vm", scope["affectedHosts"])
        self.assertIn("gateway2-vm", scope["affectedHosts"])

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
        self.assertEqual(
            gates["static-validation"]["failureClassification"], "repository-wide"
        )

    def test_failed_consumer_surface_keeps_owner_outcome_incomplete(self) -> None:
        self.failed_consumer_gate = ".#fleetLifecycleConsumers.gateway2-vm.rendered.route"

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
        report = self.read_evidence()
        self.assertEqual(report["outcome"], "incomplete")
        gate = next(
            item
            for item in report["gates"]
            if item["id"] == "consumer:gateway2-vm:route"
        )
        self.assertEqual(gate["status"], "failed")
        self.assertEqual(gate["applicability"], "applicable")
        self.assertEqual(gate["failureClassification"], "target-service")

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

    def test_stateful_run_requires_explicit_live_mutation_mode(self) -> None:
        result = self.run_command(
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--mutation-mode live", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_stateful_run_delegates_guarded_phases_and_records_receipts(self) -> None:
        result = self.run_command(
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_evidence()
        self.assertEqual(report["outcome"], "complete")
        self.assertTrue(report["mutationAllowed"])
        gates = {gate["id"]: gate for gate in report["gates"]}
        for gate_id in (
            "readiness",
            "pre-change-backup",
            "dry-activate:testbed-vm",
            "guarded-deployment:testbed-vm",
            "owning-host-health:testbed-vm",
            "backup-timer",
            "snapshot",
            "non-destructive-restore-check",
        ):
            self.assertEqual(gates[gate_id]["status"], "passed", gate_id)

        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        wrapper = "scripts/testbed-vm/upgrade-testbed-vm.sh"
        self.assertEqual(
            commands,
            [
                "nix eval --json .#fleetLifecycleConsumers",
                f"{wrapper} check-upgrade-readiness",
                f"{wrapper} create-pre-upgrade-backup",
                f"{wrapper} dry-activate-testbed-vm",
                f"{wrapper} deploy-testbed-vm",
                f"{wrapper} verify-testbed-vm",
            ],
        )
        self.assertFalse(any("restore-" in command for command in commands))

        receipt = json.loads((self.receipts / "pre-change-backup.json").read_text())
        self.assertEqual(receipt["targetScope"], report["scope"])
        self.assertEqual(receipt["lifecycleAction"], "edit")
        self.assertTrue(receipt["repositoryStateFingerprint"])
        self.assertTrue(receipt["completedAt"])
        self.assertTrue(receipt["backupEvidence"]["outputSha256"])
        for gate_id in ("backup-timer", "snapshot", "non-destructive-restore-check"):
            evidence = gates[gate_id]["verificationEvidence"]
            self.assertEqual(evidence["delegatedCommand"][-1], "verify-testbed-vm")
            self.assertTrue(evidence["outputSha256"])
            verification_receipt = json.loads(
                (self.receipts / f"{gate_id}.json").read_text()
            )
            self.assertEqual(
                verification_receipt["verificationEvidence"], evidence
            )

    def test_stateful_run_validates_consumers_without_switching_them(self) -> None:
        result = self.run_command(
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "generated",
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_evidence()
        gates = {gate["id"]: gate for gate in report["gates"]}
        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        for host in report["scope"]["consumerHosts"]:
            for surface in report["scope"]["consumerSurfaces"][host]:
                self.assertEqual(gates[f"consumer:{host}:{surface}"]["status"], "passed")
            if host == report["scope"]["runtimeHost"]:
                continue
            self.assertEqual(gates[f"build:{host}"]["status"], "passed")
            self.assertEqual(gates[f"dry-activate:{host}"]["status"], "passed")
            self.assertEqual(
                gates[f"consumer-host-health:{host}"]["status"], "passed"
            )
            self.assertIn(f"colmena build --on {host}", commands)
            self.assertIn(f"colmena apply --on {host} dry-activate", commands)
            self.assertNotIn(f"colmena apply --on {host} switch", commands)
            consumer_gate = gates[f"consumer-host-health:{host}"]
            self.assertIn("outputSha256", consumer_gate)
            self.assertIn("/test-", consumer_gate["command"][0])
            self.assertIn(consumer_gate["command"][0], commands)

    def test_stateful_run_rejects_receipts_inside_worktree(self) -> None:
        result = self.run_command(
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--receipt-dir",
            str(self.root / "fleet-receipts"),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("receipt directory", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_stateful_resume_skips_completed_phases_for_unchanged_run(self) -> None:
        arguments = (
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--receipt-dir",
            str(self.receipts),
        )
        first = self.run_command(*arguments)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.command_log.unlink()

        resumed = self.run_command(*arguments, "--resume")

        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertEqual(
            self.command_log.read_text(encoding="utf-8").splitlines(),
            ["nix eval --json .#fleetLifecycleConsumers"],
        )
        gates = {gate["id"]: gate for gate in self.read_evidence()["gates"]}
        self.assertTrue(all(gate["resumed"] for gate in gates.values() if gate["id"] != "scope-discovery"))

    def test_stateful_resume_continues_after_interrupted_phase(self) -> None:
        arguments = (
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--receipt-dir",
            str(self.receipts),
        )
        self.failed_upgrade_phase = "deploy-testbed-vm"
        interrupted = self.run_command(*arguments)
        self.assertNotEqual(interrupted.returncode, 0)
        first_commands = self.command_log.read_text(encoding="utf-8").splitlines()
        self.assertIn(
            "scripts/testbed-vm/upgrade-testbed-vm.sh create-pre-upgrade-backup",
            first_commands,
        )
        self.assertNotIn(
            "scripts/testbed-vm/upgrade-testbed-vm.sh verify-testbed-vm", first_commands
        )
        del self.failed_upgrade_phase
        self.command_log.unlink()

        resumed = self.run_command(*arguments, "--resume")

        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertEqual(
            self.command_log.read_text(encoding="utf-8").splitlines(),
            [
                "nix eval --json .#fleetLifecycleConsumers",
                "scripts/testbed-vm/upgrade-testbed-vm.sh deploy-testbed-vm",
                "scripts/testbed-vm/upgrade-testbed-vm.sh verify-testbed-vm",
            ],
        )

    def test_stateful_resume_rejects_missing_phase_receipt(self) -> None:
        arguments = (
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--receipt-dir",
            str(self.receipts),
        )
        first = self.run_command(*arguments)
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.receipts / "pre-change-backup.json").unlink()
        self.command_log.unlink()

        resumed = self.run_command(*arguments, "--resume")

        self.assertNotEqual(resumed.returncode, 0)
        self.assertIn("phase receipt", resumed.stderr)
        self.assertFalse(self.command_log.exists())

    def test_stateful_resume_rejects_changed_repository_state(self) -> None:
        arguments = (
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--receipt-dir",
            str(self.receipts),
        )
        first = self.run_command(*arguments)
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.root / "changed.nix").write_text("{}\n", encoding="utf-8")
        self.command_log.unlink()

        resumed = self.run_command(*arguments, "--resume")

        self.assertNotEqual(resumed.returncode, 0)
        self.assertIn("repository state", resumed.stderr)
        self.assertFalse(self.command_log.exists())

    def test_stateful_resume_rejects_changed_target_scope(self) -> None:
        base_arguments = (
            "run",
            "--action",
            "edit",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--receipt-dir",
            str(self.receipts),
        )
        first = self.run_command(*base_arguments, "--host", "testbed-vm")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.command_log.unlink()

        resumed = self.run_command(
            *base_arguments, "--host", "monitoring-vm", "--resume"
        )

        self.assertNotEqual(resumed.returncode, 0)
        self.assertIn("target scope", resumed.stderr)
        self.assertFalse(self.command_log.exists())

    def test_stateful_resume_rejects_tampered_recorded_scope(self) -> None:
        arguments = (
            "run",
            "--action",
            "edit",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--receipt-dir",
            str(self.receipts),
        )
        first = self.run_command(*arguments)
        self.assertEqual(first.returncode, 0, first.stderr)
        manifest_path = self.receipts / "run.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["targetScope"]["affectedHosts"].append("gateway-vm")
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        for receipt_path in self.receipts.glob("*.json"):
            if receipt_path == manifest_path:
                continue
            receipt = json.loads(receipt_path.read_text())
            receipt["targetScope"] = manifest["targetScope"]
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        self.command_log.unlink()

        resumed = self.run_command(*arguments, "--resume")

        self.assertNotEqual(resumed.returncode, 0)
        self.assertIn("target scope changed", resumed.stderr)
        self.assertEqual(
            self.command_log.read_text(encoding="utf-8").splitlines(),
            ["nix eval --json .#fleetLifecycleConsumers"],
        )


if __name__ == "__main__":
    unittest.main()
