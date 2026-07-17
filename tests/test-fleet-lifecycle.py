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
        self.write_executable(
            self.root / "scripts" / "testbed-vm" / "test-removal-evidence.sh",
            f"#!{self.shell}\n"
            "set -eu\n"
            "printf 'scripts/testbed-vm/test-removal-evidence.sh %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n"
            "printf '%s verified\\n' \"$*\"\n",
        )
        self.write_executable(
            self.root / "scripts" / "testbed-vm" / "test-testbed-services.sh",
            f"#!{self.shell}\n"
            "printf 'scripts/testbed-vm/test-testbed-services.sh\\n' >> \"$FLEET_TEST_COMMAND_LOG\"\n",
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
            deploy_name = f"deploy-{host.removesuffix('-vm')}.sh"
            self.write_executable(
                script_dir / deploy_name,
                f"#!{self.shell}\n"
                f"printf 'scripts/{host}/{deploy_name}\\n' >> \"$FLEET_TEST_COMMAND_LOG\"\n",
            )
        self.write_executable(
            self.root / "scripts" / "productivity-vm" / "upgrade-productivity-vm.sh",
            f"#!{self.shell}\n"
            "set -eu\n"
            "printf 'scripts/productivity-vm/upgrade-productivity-vm.sh %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n"
            "printf 'verified phase %s\\n' \"$*\"\n",
        )
        self.write_executable(
            self.root / "scripts" / "test-move-evidence.sh",
            f"#!{self.shell}\n"
            "set -eu\n"
            "printf 'scripts/test-move-evidence.sh %s\\n' \"$*\" >> \"$FLEET_TEST_COMMAND_LOG\"\n"
            "printf '%s\\n' ' true '\n",
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

    def write_removal_manifest(
        self,
        *,
        state_disposition: str = "retained",
        snapshot_disposition: str = "retained",
    ) -> Path:
        surface_names = (
            "runtime",
            "listeners",
            "routes",
            "homepage",
            "authentication",
            "monitoring",
            "secrets",
            "backup",
            "restore",
            "smoke",
            "documentation",
            "endpoint",
        )
        inventory = {
            surface: {
                "resources": [
                    {
                        "id": f"example-{surface}",
                        "resource": f"example {surface} resource",
                        "ownership": "unshared",
                        "disposition": "remove",
                        "verification": {
                            "command": [
                                "scripts/testbed-vm/test-removal-evidence.sh",
                                surface,
                            ],
                            "expectedStdout": f"{surface} verified\n",
                        },
                    }
                ]
            }
            for surface in surface_names
        }
        inventory["routes"]["resources"].append(
            {
                "id": "shared-route-generator",
                "resource": "fleet Gateway route generator",
                "ownership": "shared",
                "disposition": "retain",
                "verification": {
                    "command": [
                        "scripts/testbed-vm/test-removal-evidence.sh",
                        "shared-route-generator",
                    ],
                    "expectedStdout": "shared-route-generator verified\n",
                },
            }
        )
        inventory["documentation"]["resources"].append(
            {
                "id": "retained-recovery-doc",
                "resource": "hosts/testbed-vm/README.md retained recovery note",
                "ownership": "unshared",
                "disposition": "retain",
                "verification": {
                    "command": [
                        "scripts/testbed-vm/test-removal-evidence.sh",
                        "retained-recovery-doc",
                    ],
                    "expectedStdout": "retained-recovery-doc verified\n",
                },
            }
        )
        def recovery_disposition(disposition: str, material: str) -> dict[str, str]:
            if disposition == "not_applicable":
                return {
                    "disposition": disposition,
                    "reason": "the stateless service has no recovery material",
                }
            return {
                "disposition": disposition,
                "recoveryMaterial": material,
                "documentation": "hosts/testbed-vm/README.md",
            }

        retained_recovery = state_disposition in ("retained", "exported") or snapshot_disposition in (
            "retained",
            "exported",
        )
        manifest = {
            "schemaVersion": 1,
            "service": "example",
            "state": recovery_disposition(state_disposition, "/srv/appsdata/example"),
            "snapshots": recovery_disposition(
                snapshot_disposition, "restic snapshots tagged example"
            ),
            "inventory": inventory,
            "retainedRecoveryChecks": [
                {
                    "id": "retained-recovery-material",
                    "command": [
                        "scripts/testbed-vm/test-removal-evidence.sh",
                        "retained-recovery-material",
                    ],
                    "expectedStdout": "retained-recovery-material verified\n",
                }
            ]
            if retained_recovery
            else [],
            "survivingServiceChecks": [
                {
                    "id": "surviving-services",
                    "command": [
                        "scripts/testbed-vm/test-removal-evidence.sh",
                        "surviving-services",
                    ],
                    "expectedStdout": "surviving-services verified\n",
                }
            ],
        }
        path = self.root / ".git" / "removal-manifest.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return path

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

    def test_move_plan_records_ownership_state_and_cutover_contract(self) -> None:
        result = self.run_command(
            "plan",
            "--action",
            "move",
            "--service-class",
            "stateful",
            "--service",
            "example",
            "--source-host",
            "productivity-vm",
            "--target-host",
            "testbed-vm",
            "--state-boundary",
            "/srv/appsdata/example",
            "--transfer-method",
            "restore an explicitly selected source snapshot on the target",
            "--consistency-window",
            "source quiesced from recovery point through route cutover",
            "--cutover-order",
            "backup, transfer, target, consumers, source retirement",
            "--move-verification-command",
            "scripts/test-move-evidence.sh",
        )

        self.assertNotEqual(result.returncode, 0)
        report = self.read_evidence()
        self.assertEqual(
            report["movePlan"],
            {
                "service": "example",
                "sourceOwner": "productivity-vm",
                "targetOwner": "testbed-vm",
                "stateBoundary": "/srv/appsdata/example",
                "transferMethod": "restore an explicitly selected source snapshot on the target",
                "consistencyWindow": "source quiesced from recovery point through route cutover",
                "cutoverOrder": "backup, transfer, target, consumers, source retirement",
                "verificationCommand": "scripts/test-move-evidence.sh",
            },
        )
        self.assertEqual(report["scope"]["runtimeHost"], "testbed-vm")
        self.assertEqual(report["scope"]["sourceHost"], "productivity-vm")
        self.assertEqual(report["outcome"], "incomplete")
        gates = {item["id"]: item for item in report["gates"]}
        self.assertIn("source-recovery-point:productivity-vm", gates)
        self.assertIn("target-secrets-permissions:testbed-vm", gates)
        self.assertIn("source-retirement:productivity-vm", gates)
        self.assertEqual(gates["transfer-evidence"]["status"], "not_run")
        self.assertEqual(
            self.command_log.read_text(encoding="utf-8").splitlines(),
            ["nix eval --json .#fleetLifecycleConsumers"],
        )

    def test_move_run_proves_target_and_consumers_before_source_retirement(self) -> None:
        result = self.run_command(
            "run",
            "--action",
            "move",
            "--service-class",
            "stateful",
            "--service",
            "example",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "generated",
            "--source-host",
            "productivity-vm",
            "--target-host",
            "testbed-vm",
            "--state-boundary",
            "/srv/appsdata/example",
            "--transfer-method",
            "restore an explicitly selected source snapshot on the target",
            "--consistency-window",
            "source quiesced from recovery point through route cutover",
            "--cutover-order",
            "backup, transfer, target, consumers, source retirement",
            "--move-verification-command",
            "scripts/test-move-evidence.sh",
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_evidence()
        gates = {item["id"]: item for item in report["gates"]}
        for gate_id in (
            "source-recovery-point:productivity-vm",
            "transfer-evidence",
            "target-secrets-permissions:testbed-vm",
            "owning-host-health:testbed-vm",
            "target-backup-recovery-ownership:testbed-vm",
            "source-retirement:productivity-vm",
            "old-runtime-absence:productivity-vm",
            "old-listener-absence:productivity-vm",
            "old-launcher-absence:productivity-vm",
            "old-route-target-absence:productivity-vm",
            "old-backup-responsibility-absence:productivity-vm",
        ):
            self.assertEqual(gates[gate_id]["status"], "passed", gate_id)
            if gate_id not in (
                "source-recovery-point:productivity-vm",
                "owning-host-health:testbed-vm",
                "source-retirement:productivity-vm",
            ):
                self.assertTrue(gates[gate_id].get("outputSha256"), gate_id)

        recovery_hash = gates["source-recovery-point:productivity-vm"]["outputSha256"]
        self.assertIn(recovery_hash, gates["transfer-evidence"]["command"])
        self.assertNotIn("\n true \n", result.stderr)

        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        target_health = commands.index(
            "scripts/testbed-vm/upgrade-testbed-vm.sh verify-testbed-vm"
        )
        consumer_health = max(
            commands.index(command)
            for command in commands
            if command.startswith("scripts/gateway")
            or command.startswith("scripts/monitoring")
            or command.startswith("scripts/productivity-vm/test-")
        )
        source_retirement = commands.index(
            "scripts/productivity-vm/upgrade-productivity-vm.sh deploy-productivity-vm"
        )
        self.assertLess(target_health, source_retirement)
        self.assertLess(consumer_health, source_retirement)
        for host in ("gateway-vm", "gateway2-vm", "monitoring-vm"):
            deploy = f"scripts/{host}/deploy-{host.removesuffix('-vm')}.sh"
            health = next(
                command
                for command in commands
                if command.startswith(f"scripts/{host}/test-")
            )
            self.assertLess(commands.index(deploy), commands.index(health))
            self.assertLess(commands.index(health), source_retirement)
        self.assertFalse(any("restore-" in command for command in commands))

    def test_move_cutover_failure_preserves_source_and_never_restores(self) -> None:
        self.failed_upgrade_phase = "deploy-testbed-vm"
        result = self.run_command(
            "run",
            "--action",
            "move",
            "--service-class",
            "stateful",
            "--service",
            "example",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--source-host",
            "productivity-vm",
            "--target-host",
            "testbed-vm",
            "--state-boundary",
            "/srv/appsdata/example",
            "--transfer-method",
            "restore an explicitly selected source snapshot on the target",
            "--consistency-window",
            "source quiesced from recovery point through route cutover",
            "--cutover-order",
            "backup, transfer, target, consumers, source retirement",
            "--move-verification-command",
            "scripts/test-move-evidence.sh",
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertNotEqual(result.returncode, 0)
        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        self.assertIn(
            "scripts/productivity-vm/upgrade-productivity-vm.sh create-pre-upgrade-backup",
            commands,
        )
        self.assertNotIn(
            "scripts/productivity-vm/upgrade-productivity-vm.sh deploy-productivity-vm",
            commands,
        )
        self.assertFalse(any("restore-" in command for command in commands))
        gates = {item["id"]: item for item in self.read_evidence()["gates"]}
        self.assertEqual(
            gates["source-retirement:productivity-vm"]["status"], "not_run"
        )

    def test_move_rejects_mutating_verification_command_before_scope_discovery(self) -> None:
        result = self.run_command(
            "plan",
            "--action",
            "move",
            "--service-class",
            "stateful",
            "--service",
            "example",
            "--source-host",
            "productivity-vm",
            "--target-host",
            "testbed-vm",
            "--state-boundary",
            "/srv/appsdata/example",
            "--transfer-method",
            "operator-controlled transfer",
            "--consistency-window",
            "source quiesced through cutover",
            "--cutover-order",
            "backup, transfer, target, consumers, source retirement",
            "--move-verification-command",
            "scripts/testbed-vm/deploy-testbed.sh",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("repository test script", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_upgrade_plan_records_reproducibility_migration_and_rollback_decisions(self) -> None:
        result = self.run_command(
            "plan",
            "--action",
            "upgrade",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--current-version-source",
            "modules/testbed/services/example.nix: image tag 1.2.3",
            "--target-kind",
            "image",
            "--target-version",
            "ghcr.io/example/app:1.3.0@sha256:" + "a" * 64,
            "--immutable-reference",
            "sha256:" + "a" * 64,
            "--migration-requirements",
            "run the documented 1.3 schema migration",
            "--dependency-compatibility",
            "PostgreSQL 16 remains supported",
            "--downgrade-support",
            "unsupported after the schema migration",
            "--intermediate-versions",
            "none required from 1.2.3",
            "--configuration-rollback",
            "switch to the previous Nix generation only before migration",
            "--data-rollback",
            "restore the explicitly selected pre-upgrade snapshot",
        )

        self.assertNotEqual(result.returncode, 0)
        report = self.read_evidence()
        self.assertEqual(report["action"], "upgrade")
        self.assertEqual(
            report["upgradePlan"]["targetVersion"],
            "ghcr.io/example/app:1.3.0@sha256:" + "a" * 64,
        )
        self.assertTrue(report["upgradePlan"]["targetIsImmutable"])
        self.assertIn("migration", report["upgradePlan"]["migrationRequirements"])
        self.assertNotEqual(
            report["rollbackBoundaries"]["configuration"],
            report["rollbackBoundaries"]["data"],
        )
        self.assertEqual(report["outcome"], "incomplete")
        self.assertEqual(
            self.command_log.read_text(encoding="utf-8").splitlines(),
            ["nix eval --json .#fleetLifecycleConsumers"],
        )

    def test_upgrade_plan_rejects_floating_target_before_scope_discovery(self) -> None:
        result = self.run_command(
            "plan",
            "--action",
            "upgrade",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--current-version-source",
            "modules/testbed/services/example.nix",
            "--target-kind",
            "image",
            "--target-version",
            "ghcr.io/example/app:latest",
            "--immutable-reference",
            "sha256:" + "a" * 64,
            "--migration-requirements",
            "none",
            "--dependency-compatibility",
            "compatible",
            "--downgrade-support",
            "unsupported",
            "--intermediate-versions",
            "none",
            "--configuration-rollback",
            "previous generation",
            "--data-rollback",
            "explicit snapshot restore",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("immutable", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_upgrade_plan_rejects_image_with_implicit_latest_tag(self) -> None:
        result = self.run_command(
            "plan",
            "--action",
            "upgrade",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--current-version-source",
            "modules/testbed/services/example.nix",
            "--target-kind",
            "image",
            "--target-version",
            "ghcr.io/example/app",
            "--immutable-reference",
            "sha256:" + "a" * 64,
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
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("immutable", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_upgrade_plan_rejects_versioned_image_without_digest(self) -> None:
        result = self.run_command(
            "plan", "--action", "upgrade", "--host", "testbed-vm",
            "--service-class", "stateful",
            "--current-version-source", "modules/testbed/services/example.nix",
            "--target-kind", "image",
            "--target-version", "example-app:1.3.0",
            "--immutable-reference", "sha256:" + "a" * 64,
            "--migration-requirements", "none",
            "--dependency-compatibility", "compatible",
            "--downgrade-support", "supported",
            "--intermediate-versions", "none",
            "--configuration-rollback", "previous generation",
            "--data-rollback", "explicit snapshot restore",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("immutable", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_stateless_upgrade_plan_uses_generated_consumers_without_backup(self) -> None:
        result = self.run_command(
            "plan", "--action", "upgrade", "--host", "testbed-vm",
            "--service-class", "stateless",
            "--current-version-source", "flake.lock: nixpkgs package 1.2.3",
            "--target-kind", "package",
            "--target-version", "1.3.0",
            "--immutable-reference", "a" * 40,
            "--migration-requirements", "none",
            "--dependency-compatibility", "compatible",
            "--downgrade-support", "supported",
            "--intermediate-versions", "none",
            "--configuration-rollback", "previous generation",
            "--data-rollback", "not applicable because the service is stateless",
        )

        self.assertNotEqual(result.returncode, 0)
        report = self.read_evidence()
        self.assertEqual(report["scope"]["consumerImpact"], "generated")
        gates = {gate["id"]: gate for gate in report["gates"]}
        self.assertEqual(gates["pre-change-backup"]["status"], "not_applicable")
        self.assertTrue(report["scope"]["consumerHosts"])

    def test_upgrade_run_requires_explicit_migration_and_rollback_decisions(self) -> None:
        result = self.run_command(
            "run",
            "--action",
            "upgrade",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--target-version",
            "ghcr.io/example/app:1.3.0@sha256:" + "b" * 64,
            "--target-kind",
            "image",
            "--immutable-reference",
            "sha256:" + "b" * 64,
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("current-version-source", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_upgrade_run_backs_up_before_owner_deployment_and_never_restores(self) -> None:
        result = self.run_command(
            "run",
            "--action",
            "upgrade",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--current-version-source",
            "modules/testbed/services/example.nix: 1.2.3",
            "--target-kind",
            "package",
            "--target-version",
            "1.3.0",
            "--immutable-reference",
            "b" * 40,
            "--migration-requirements",
            "schema migration required",
            "--dependency-compatibility",
            "dependencies compatible",
            "--downgrade-support",
            "not supported after migration",
            "--intermediate-versions",
            "none required",
            "--configuration-rollback",
            "previous generation before migration only",
            "--data-rollback",
            "explicit pre-upgrade snapshot restore",
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        backup_index = commands.index(
            "scripts/testbed-vm/upgrade-testbed-vm.sh create-pre-upgrade-backup"
        )
        deploy_index = commands.index(
            "scripts/testbed-vm/upgrade-testbed-vm.sh deploy-testbed-vm"
        )
        self.assertLess(backup_index, deploy_index)
        self.assertFalse(any("restore" in command for command in commands))
        report = self.read_evidence()
        self.assertEqual(report["outcome"], "complete")
        self.assertEqual(report["scope"]["upgradePlan"], report["upgradePlan"])

    def test_removal_plan_records_complete_inventory_and_recovery_disposition(self) -> None:
        manifest_path = self.write_removal_manifest()

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        report = self.read_evidence()
        removal = report["removalPlan"]
        self.assertEqual(removal["service"], "example")
        self.assertEqual(removal["state"]["disposition"], "retained")
        self.assertEqual(removal["snapshots"]["disposition"], "retained")
        self.assertEqual(
            set(removal["inventory"]),
            {
                "runtime",
                "listeners",
                "routes",
                "homepage",
                "authentication",
                "monitoring",
                "secrets",
                "backup",
                "restore",
                "smoke",
                "documentation",
                "endpoint",
            },
        )
        shared = removal["inventory"]["routes"]["resources"][1]
        self.assertEqual(shared["ownership"], "shared")
        self.assertEqual(shared["disposition"], "retain")
        self.assertEqual(report["scope"]["removalPlan"], removal)
        self.assertEqual(report["scope"]["consumerImpact"], "generated")
        self.assertIn("gateway-vm", report["scope"]["consumerHosts"])
        self.assertIn("monitoring-vm", report["scope"]["consumerHosts"])
        self.assertEqual(report["outcome"], "incomplete")
        self.assertEqual(
            self.command_log.read_text(encoding="utf-8").splitlines(),
            ["nix eval --json .#fleetLifecycleConsumers"],
        )

    def test_removal_rejects_shared_resource_deletion_before_scope_discovery(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["routes"]["resources"][1]["disposition"] = "remove"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("shared resources must be retained", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_rejects_incomplete_inventory_before_scope_discovery(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        del manifest["inventory"]["authentication"]
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authentication", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_rejects_mutating_verification_command(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["runtime"]["resources"][0]["verification"]["command"] = [
            "rm",
            "-rf",
            "/srv/appsdata/example",
        ]
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "run",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inside the repository scripts directory", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_rejects_generic_network_verification_command(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["endpoint"]["resources"][0]["verification"]["command"] = [
            "curl",
            "-X",
            "DELETE",
            "https://example.invalid",
        ]
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inside the repository scripts directory", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_rejects_verification_script_outside_repository(self) -> None:
        outside_script = self.root.parent / "test-outside-removal.sh"
        self.write_executable(outside_script, f"#!{self.shell}\nprintf 'absent\\n'\n")
        self.addCleanup(outside_script.unlink, missing_ok=True)
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["endpoint"]["resources"][0]["verification"]["command"] = [
            "scripts/../../test-outside-removal.sh",
        ]
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inside the repository scripts directory", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_requires_former_endpoint_absence_proof(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["endpoint"] = {
            "notApplicableReason": "endpoint proof omitted"
        }
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("endpoint requires an unshared removal resource", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_requires_runtime_absence_proof(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["runtime"] = {
            "notApplicableReason": "runtime proof omitted"
        }
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runtime requires an unshared removal resource", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_rejects_host_local_scope_when_generated_surfaces_apply(self) -> None:
        manifest_path = self.write_removal_manifest()

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--consumer-impact",
            "host-local",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("generated removal surfaces", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_requires_shared_generator_proof_for_generated_surfaces(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["routes"]["resources"] = [
            manifest["inventory"]["routes"]["resources"][0]
        ]
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("shared generator", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_rejects_destruction_without_explicit_authority(self) -> None:
        manifest_path = self.write_removal_manifest(state_disposition="destroyed")

        result = self.run_command(
            "run",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--authorize-destruction", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_removal_run_switches_affected_hosts_and_proves_live_absence(self) -> None:
        manifest_path = self.write_removal_manifest()

        result = self.run_command(
            "run",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "generated",
            "--removal-manifest",
            str(manifest_path),
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_evidence()
        self.assertEqual(report["outcome"], "complete")
        gates = {gate["id"]: gate for gate in report["gates"]}
        for surface in (
            "runtime",
            "listeners",
            "routes",
            "homepage",
            "authentication",
            "monitoring",
            "secrets",
            "backup",
            "restore",
            "smoke",
            "documentation",
            "endpoint",
        ):
            self.assertEqual(gates[f"removed:{surface}:example-{surface}"]["status"], "passed")
        self.assertEqual(gates["retained:routes:shared-route-generator"]["status"], "passed")
        self.assertEqual(gates["retained:documentation:retained-recovery-doc"]["status"], "passed")
        self.assertEqual(gates["surviving:surviving-services"]["status"], "passed")
        recovery_after = gates["retained-recovery-after:retained-recovery-material"]
        self.assertEqual(recovery_after["status"], "passed")
        self.assertEqual(
            recovery_after["outputSha256"],
            gates["retained-recovery-before:retained-recovery-material"]["outputSha256"],
        )

        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        owner_deploy = commands.index(
            "scripts/testbed-vm/upgrade-testbed-vm.sh deploy-testbed-vm"
        )
        first_absence = commands.index(
            "scripts/testbed-vm/test-removal-evidence.sh runtime"
        )
        self.assertLess(owner_deploy, first_absence)
        for host in ("gateway-vm", "gateway2-vm", "monitoring-vm"):
            consumer_switch = commands.index(f"colmena apply --on {host} switch")
            self.assertLess(owner_deploy, consumer_switch)
            self.assertLess(consumer_switch, first_absence)
        self.assertFalse(any("restore" in command and "test-removal" not in command for command in commands))

    def test_removal_run_stops_when_live_absence_proof_does_not_match(self) -> None:
        manifest_path = self.write_removal_manifest()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["inventory"]["runtime"]["resources"][0]["verification"][
            "expectedStdout"
        ] = "runtime absent\n"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "run",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateful",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "generated",
            "--removal-manifest",
            str(manifest_path),
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertNotEqual(result.returncode, 0)
        gates = {gate["id"]: gate for gate in self.read_evidence()["gates"]}
        self.assertEqual(gates["removed:runtime:example-runtime"]["status"], "failed")
        self.assertEqual(gates["removed:listeners:example-listeners"]["status"], "not_run")
        self.assertEqual(gates["surviving:surviving-services"]["status"], "not_run")

    def test_stateless_removal_run_marks_backup_not_applicable_and_proves_absence(self) -> None:
        manifest_path = self.write_removal_manifest(
            state_disposition="not_applicable",
            snapshot_disposition="not_applicable",
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for surface in ("routes", "homepage", "authentication", "monitoring"):
            manifest["inventory"][surface] = {
                "notApplicableReason": "the stateless service is host-local"
            }
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        result = self.run_command(
            "run",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--removal-manifest",
            str(manifest_path),
            "--receipt-dir",
            str(self.receipts),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_evidence()
        gates = {gate["id"]: gate for gate in report["gates"]}
        self.assertEqual(report["outcome"], "complete")
        self.assertEqual(gates["pre-change-backup"]["status"], "not_applicable")
        self.assertIn("stateless", gates["pre-change-backup"]["reason"])
        self.assertEqual(gates["removed:runtime:example-runtime"]["status"], "passed")
        commands = self.command_log.read_text(encoding="utf-8").splitlines()
        self.assertIn("colmena apply --on testbed-vm switch", commands)
        self.assertIn("scripts/testbed-vm/test-testbed-services.sh", commands)
        self.assertFalse(any("create-pre-upgrade-backup" in command for command in commands))

    def test_stateless_removal_rejects_recovery_material_dispositions(self) -> None:
        manifest_path = self.write_removal_manifest()

        result = self.run_command(
            "plan",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--removal-manifest",
            str(manifest_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stateless removal", result.stderr)
        self.assertIn("not_applicable", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_stateless_removal_resume_preserves_not_applicable_backup_evidence(self) -> None:
        manifest_path = self.write_removal_manifest(
            state_disposition="not_applicable",
            snapshot_disposition="not_applicable",
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for surface in ("routes", "homepage", "authentication", "monitoring"):
            manifest["inventory"][surface] = {
                "notApplicableReason": "the stateless service is host-local"
            }
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        arguments = (
            "run",
            "--action",
            "removal",
            "--host",
            "testbed-vm",
            "--service-class",
            "stateless",
            "--mutation-mode",
            "live",
            "--consumer-impact",
            "host-local",
            "--removal-manifest",
            str(manifest_path),
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
        self.assertEqual(gates["pre-change-backup"]["status"], "not_applicable")
        self.assertTrue(gates["pre-change-backup"]["resumed"])

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
