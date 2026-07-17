#!/usr/bin/env python3
"""Run the canonical production service lifecycle and emit structured evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


STATUSES = ("passed", "failed", "blocked", "not_run", "not_applicable")
FLOATING_TARGETS = {"edge", "latest", "main", "master", "rolling", "stable"}
OCI_DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")
CONTENT_PIN = re.compile(
    r"(?:[0-9a-f]{40,64}|sha256[-:][A-Za-z0-9+/=]{32,}|/nix/store/[a-z0-9]{32}-[^/]+)$"
)
REMOVAL_SURFACES = (
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
RECOVERY_DISPOSITIONS = {"retained", "exported", "destroyed", "not_applicable"}


def immutable_upgrade_target(target: str, target_kind: str, immutable_reference: str) -> bool:
    """Return whether an operator-selected release target is reproducible."""
    normalized = target.strip().lower().removesuffix("/")
    final_component = normalized.rsplit("/", 1)[-1]
    tag = final_component.rsplit(":", 1)[-1] if ":" in final_component else final_component
    if not normalized or tag in FLOATING_TARGETS:
        return False
    if target_kind == "image":
        match = OCI_DIGEST.search(normalized)
        return match is not None and immutable_reference.lower() == match.group(0)[1:]
    return CONTENT_PIN.fullmatch(immutable_reference) is not None


def upgrade_plan(arguments: argparse.Namespace) -> dict[str, Any] | None:
    if arguments.action != "upgrade":
        return None
    return {
        "currentVersionSource": arguments.current_version_source,
        "targetKind": arguments.target_kind,
        "targetVersion": arguments.target_version,
        "immutableReference": arguments.immutable_reference,
        "targetIsImmutable": immutable_upgrade_target(
            arguments.target_version,
            arguments.target_kind,
            arguments.immutable_reference,
        ),
        "migrationRequirements": arguments.migration_requirements,
        "dependencyCompatibility": arguments.dependency_compatibility,
        "downgradeSupport": arguments.downgrade_support,
        "intermediateVersions": arguments.intermediate_versions,
        "configurationRollback": arguments.configuration_rollback,
        "dataRollback": arguments.data_rollback,
    }


def move_plan(arguments: argparse.Namespace) -> dict[str, Any] | None:
    if arguments.action != "move":
        return None
    plan = {
        "service": arguments.service,
        "sourceOwner": arguments.source_host,
        "targetOwner": arguments.target_host,
        "stateBoundary": arguments.state_boundary,
        "transferMethod": arguments.transfer_method,
        "consistencyWindow": arguments.consistency_window,
        "cutoverOrder": arguments.cutover_order,
        "verificationCommand": arguments.move_verification_command,
    }
    return plan


def validate_verification(check: Any, context: str) -> None:
    if not isinstance(check, dict):
        raise ValueError(f"{context} must be an object")
    command = check.get("command")
    if (
        not isinstance(command, list)
        or not command
        or not all(isinstance(argument, str) and argument for argument in command)
    ):
        raise ValueError(f"{context} requires a non-empty command array")
    expected_exit_codes = check.get("expectedExitCodes", [0])
    if (
        not isinstance(expected_exit_codes, list)
        or not expected_exit_codes
        or not all(isinstance(code, int) for code in expected_exit_codes)
    ):
        raise ValueError(f"{context} expectedExitCodes must be a non-empty integer array")
    if "expectedStdout" in check and not isinstance(check["expectedStdout"], str):
        raise ValueError(f"{context} expectedStdout must be a string")
    executable = command[0]
    repository_test = executable.startswith("scripts/") and Path(executable).name.startswith(
        "test-"
    )
    read_only_tool = (
        executable == "rg"
        or executable == "curl"
        or (executable == "nix" and len(command) > 1 and command[1] == "eval")
    )
    if not repository_test and not read_only_tool:
        raise ValueError(
            f"{context} must use a repository test script, nix eval, rg, or curl"
        )


def validate_recovery_disposition(value: Any, context: str) -> None:
    if not isinstance(value, dict):
        raise ValueError(f"removal {context} disposition must be an object")
    disposition = value.get("disposition")
    if disposition not in RECOVERY_DISPOSITIONS:
        raise ValueError(
            f"removal {context} disposition must be retained, exported, destroyed, or not_applicable"
        )
    if disposition == "not_applicable":
        if not isinstance(value.get("reason"), str) or not value["reason"].strip():
            raise ValueError(f"removal {context} not_applicable disposition requires a reason")
        return
    for field in ("recoveryMaterial", "documentation"):
        if not isinstance(value.get(field), str) or not value[field].strip():
            raise ValueError(f"removal {context} disposition requires {field}")


def load_removal_plan(arguments: argparse.Namespace) -> dict[str, Any] | None:
    if arguments.action != "removal":
        return None
    if arguments.removal_manifest is None:
        raise ValueError("removal requires --removal-manifest")
    try:
        plan = json.loads(arguments.removal_manifest.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"removal manifest is unavailable: {arguments.removal_manifest}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"removal manifest is invalid JSON: {arguments.removal_manifest}") from error
    if not isinstance(plan, dict) or plan.get("schemaVersion") != 1:
        raise ValueError("removal manifest must be a schemaVersion 1 object")
    if not isinstance(plan.get("service"), str) or not plan["service"].strip():
        raise ValueError("removal manifest requires a service identifier")

    validate_recovery_disposition(plan.get("state"), "state")
    validate_recovery_disposition(plan.get("snapshots"), "snapshots")
    destruction_requested = any(
        plan[subject]["disposition"] == "destroyed" for subject in ("state", "snapshots")
    )
    if destruction_requested and not arguments.authorize_destruction:
        raise ValueError("destroying retained state or snapshots requires --authorize-destruction")
    plan["destructionAuthorized"] = arguments.authorize_destruction

    inventory = plan.get("inventory")
    if not isinstance(inventory, dict):
        raise ValueError("removal manifest requires an inventory object")
    missing_surfaces = [surface for surface in REMOVAL_SURFACES if surface not in inventory]
    extra_surfaces = [surface for surface in inventory if surface not in REMOVAL_SURFACES]
    if missing_surfaces or extra_surfaces:
        details = []
        if missing_surfaces:
            details.append(f"missing: {', '.join(missing_surfaces)}")
        if extra_surfaces:
            details.append(f"unsupported: {', '.join(extra_surfaces)}")
        raise ValueError(f"removal inventory surfaces are incomplete ({'; '.join(details)})")
    for surface in REMOVAL_SURFACES:
        section = inventory[surface]
        if not isinstance(section, dict):
            raise ValueError(f"removal inventory {surface} must be an object")
        resources = section.get("resources")
        if resources is None:
            reason = section.get("notApplicableReason")
            if not isinstance(reason, str) or not reason.strip():
                raise ValueError(
                    f"removal inventory {surface} requires resources or notApplicableReason"
                )
            continue
        if not isinstance(resources, list) or not resources:
            raise ValueError(f"removal inventory {surface} resources must be non-empty")
        for index, resource in enumerate(resources):
            context = f"removal inventory {surface} resource {index}"
            if not isinstance(resource, dict):
                raise ValueError(f"{context} must be an object")
            for field in ("id", "resource"):
                if not isinstance(resource.get(field), str) or not resource[field].strip():
                    raise ValueError(f"{context} requires {field}")
            if resource.get("ownership") not in ("shared", "unshared"):
                raise ValueError(f"{context} ownership must be shared or unshared")
            if resource.get("disposition") not in ("remove", "retain"):
                raise ValueError(f"{context} disposition must be remove or retain")
            if resource["ownership"] == "shared" and resource["disposition"] != "retain":
                raise ValueError("shared resources must be retained during removal")
            validate_verification(resource.get("verification"), f"{context} verification")

    retained_or_exported = any(
        plan[subject]["disposition"] in ("retained", "exported")
        for subject in ("state", "snapshots")
    )
    retained_checks = plan.get("retainedRecoveryChecks", [])
    if retained_or_exported and not retained_checks:
        raise ValueError("retained or exported recovery material requires retainedRecoveryChecks")
    if not isinstance(retained_checks, list):
        raise ValueError("retainedRecoveryChecks must be an array")
    for index, check in enumerate(retained_checks):
        if not isinstance(check, dict) or not isinstance(check.get("id"), str):
            raise ValueError(f"retainedRecoveryChecks item {index} requires an id")
        validate_verification(check, f"retainedRecoveryChecks item {index}")

    surviving_checks = plan.get("survivingServiceChecks")
    if not isinstance(surviving_checks, list) or not surviving_checks:
        raise ValueError("removal manifest requires survivingServiceChecks")
    for index, check in enumerate(surviving_checks):
        if not isinstance(check, dict) or not isinstance(check.get("id"), str):
            raise ValueError(f"survivingServiceChecks item {index} requires an id")
        validate_verification(check, f"survivingServiceChecks item {index}")
    return plan


def enrich_scope(
    scope: dict[str, Any] | None,
    arguments: argparse.Namespace,
    selected_upgrade_plan: dict[str, Any] | None,
    selected_move_plan: dict[str, Any] | None,
    selected_removal_plan: dict[str, Any] | None,
) -> None:
    if scope is None:
        return
    if selected_upgrade_plan is not None:
        scope["upgradePlan"] = selected_upgrade_plan
    if selected_move_plan is not None:
        scope["sourceHost"] = arguments.source_host
        scope["movePlan"] = selected_move_plan
    if selected_removal_plan is not None:
        scope["removalPlan"] = selected_removal_plan


def gate(
    gate_id: str,
    *,
    phase: str,
    required: bool,
    status: str = "not_run",
    reason: str | None = None,
    command: list[str] | None = None,
    exit_code: int | None = None,
    failure_classification: str = "target-service",
    applicability: str | None = None,
    expected_json: Any | None = None,
    expected_exit_codes: list[int] | None = None,
    expected_stdout: str | None = None,
    matches_gate: str | None = None,
    evidence_sha256: str | None = None,
) -> dict[str, Any]:
    if status not in STATUSES:
        raise ValueError(f"unsupported gate status: {status}")
    result: dict[str, Any] = {
        "id": gate_id,
        "phase": phase,
        "required": required,
        "status": status,
        "failureClassification": failure_classification,
    }
    if reason is not None:
        result["reason"] = reason
    if command is not None:
        result["command"] = command
    if exit_code is not None:
        result["exitCode"] = exit_code
    if applicability is not None:
        result["applicability"] = applicability
    if expected_json is not None:
        result["expectedJson"] = expected_json
    if expected_exit_codes is not None:
        result["expectedExitCodes"] = expected_exit_codes
    if expected_stdout is not None:
        result["expectedStdout"] = expected_stdout
    if matches_gate is not None:
        result["matchesGate"] = matches_gate
    if evidence_sha256 is not None:
        result["evidenceSha256"] = evidence_sha256
    return result


def run_gate(item: dict[str, Any], *, cwd: Path, capture_output: bool = False) -> bool:
    command = item["command"]
    executable = command[0]
    if "/" not in executable and shutil.which(executable) is None:
        item["status"] = "blocked"
        item["reason"] = f"required command is unavailable: {executable}"
        return False
    if "/" in executable and not (cwd / executable).is_file():
        item["status"] = "blocked"
        item["reason"] = f"required repository command is unavailable: {executable}"
        return False

    print(f"==> {item['id']}: {' '.join(command)}", file=sys.stderr, flush=True)
    try:
        should_capture = capture_output or "expectedJson" in item or "expectedStdout" in item
        run_options: dict[str, Any] = {"capture_output": True} if should_capture else {
            "stdout": sys.stderr,
            "stderr": sys.stderr,
        }
        result = subprocess.run(command, cwd=cwd, check=False, **run_options)
    except OSError as error:
        item["status"] = "blocked"
        item["reason"] = f"unable to execute required command: {error.strerror or error}"
        return False

    item["exitCode"] = result.returncode
    if should_capture:
        stdout = result.stdout or b""
        stderr = result.stderr or b""
        if not item.get("sensitiveOutput", False):
            sys.stderr.buffer.write(stdout)
            sys.stderr.buffer.write(stderr)
            sys.stderr.flush()
        item["outputSha256"] = hashlib.sha256(stdout + stderr).hexdigest()
    expected_exit_codes = item.get("expectedExitCodes", [0])
    if result.returncode not in expected_exit_codes:
        item["status"] = "failed"
        item["reason"] = (
            f"command exited with status {result.returncode}; "
            f"expected one of {expected_exit_codes}"
        )
        return False
    if "expectedJson" in item:
        try:
            actual_json = json.loads((result.stdout or b"").decode())
        except (UnicodeDecodeError, json.JSONDecodeError):
            item["status"] = "failed"
            item["reason"] = "command did not emit the required JSON evidence"
            return False
        if actual_json != item["expectedJson"]:
            item["status"] = "failed"
            item["reason"] = "rendered consumer surface is not enabled"
            return False
    if "expectedStdout" in item:
        try:
            actual_stdout = (result.stdout or b"").decode()
        except UnicodeDecodeError:
            item["status"] = "failed"
            item["reason"] = "command did not emit UTF-8 verification evidence"
            return False
        if actual_stdout != item["expectedStdout"]:
            item["status"] = "failed"
            item["reason"] = "command output did not match the required verification evidence"
            return False
    item["status"] = "passed"
    return True


def changed_paths(repo_root: Path) -> list[str] | None:
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain=v1", "--untracked-files=all"],
            cwd=repo_root,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    return [line[3:] for line in result.stdout.splitlines() if len(line) > 3]


def resolve_consumer_impact(
    repo_root: Path, runtime_host: str, action: str, requested_impact: str
) -> tuple[str, str]:
    if requested_impact != "auto":
        return requested_impact, "consumer impact was explicitly selected by the operator"
    if action in ("addition", "move", "upgrade"):
        return (
            "generated",
            f"service {action}s are validated against generated fleet consumers",
        )

    paths = changed_paths(repo_root)
    if paths is None:
        return (
            "generated",
            "Git change discovery was unavailable, so generated consumers are included conservatively",
        )
    domain = runtime_host.removesuffix("-vm")
    generated_paths = {
        f"hosts/{runtime_host}/exposure.nix",
        f"modules/{domain}/catalog.nix",
        "lib/exposure.nix",
        "lib/gateway-cluster.nix",
        "lib/service-domains.nix",
        "hosts/gateway-vm/shared.nix",
    }
    generated_prefixes = ("modules/gateway/", "modules/monitoring/checkmate-provisioning.nix")
    if any(
        path in generated_paths or path.startswith(generated_prefixes)
        for path in paths
    ):
        return "generated", "changed paths affect the generated exposure catalog"
    return "host-local", "changed paths do not affect a generated exposure surface"


def discover_scope(
    repo_root: Path, runtime_host: str, consumer_impact: str, consumer_reason: str
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    command = ["nix", "eval", "--json", ".#fleetLifecycleConsumers"]
    item = gate(
        "scope-discovery",
        phase="scope",
        required=True,
        command=command,
    )
    if shutil.which("nix") is None:
        item["status"] = "blocked"
        item["reason"] = "required command is unavailable: nix"
        return None, item

    try:
        result = subprocess.run(command, cwd=repo_root, check=False, capture_output=True, text=True)
    except OSError as error:
        item["status"] = "blocked"
        item["reason"] = f"unable to evaluate lifecycle consumers: {error.strerror or error}"
        return None, item
    item["exitCode"] = result.returncode
    if result.returncode != 0:
        item["status"] = "failed"
        item["reason"] = f"lifecycle consumer evaluation exited with status {result.returncode}"
        return None, item

    try:
        consumers = json.loads(result.stdout)
    except json.JSONDecodeError:
        item["status"] = "failed"
        item["reason"] = "lifecycle consumer evaluation did not emit valid JSON"
        return None, item

    if runtime_host not in consumers:
        item["status"] = "failed"
        item["reason"] = f"owning host is absent from evaluated fleet config: {runtime_host}"
        return None, item

    consumer_surfaces = {
        name: consumer.get("consumerSurfaces", [])
        for name, consumer in consumers.items()
    }
    consumer_evidence = {
        name: consumer.get("evidence", {})
        for name, consumer in consumers.items()
    }
    consumer_hosts = (
        [
            name
            for name, surfaces in consumer_surfaces.items()
            if surfaces
        ]
        if consumer_impact == "generated"
        else []
    )
    scope = {
        "runtimeHost": runtime_host,
        "consumerHosts": consumer_hosts,
        "consumerSurfaces": consumer_surfaces,
        "consumerEvidence": consumer_evidence,
        "affectedHosts": [runtime_host, *[host for host in consumer_hosts if host != runtime_host]],
        "consumerImpact": consumer_impact,
        "consumerReason": consumer_reason,
    }
    item["status"] = "passed"
    return scope, item


def stateless_gates(scope: dict[str, Any], operation: str) -> list[dict[str, Any]]:
    plan_reason = "plan operation reports required gates without executing them"
    initial_reason = plan_reason if operation == "plan" else None
    items = [
        gate(
            "static-validation",
            phase="static-validation",
            required=True,
            reason=initial_reason,
            command=["scripts/check.sh"],
            failure_classification="repository-wide",
        )
    ]
    items.extend(
        gate(
            f"build:{host}",
            phase="affected-host-build",
            required=True,
            reason=initial_reason,
            command=["colmena", "build", "--on", host],
        )
        for host in scope["affectedHosts"]
    )
    items.append(
        gate(
            "pre-change-backup",
            phase="pre-change-backup",
            required=False,
            status="not_applicable",
            reason="the declared service class is stateless, so no restore-critical state is at risk",
        )
    )
    items.extend(
        gate(
            f"dry-activate:{host}",
            phase="dry-activation",
            required=True,
            reason=initial_reason,
            command=["colmena", "apply", "--on", host, "dry-activate"],
        )
        for host in scope["affectedHosts"]
    )
    items.append(
        gate(
            "guarded-deployment",
            phase="guarded-deployment",
            required=False,
            status="not_applicable",
            reason=(
                "this validation operation is non-mutating; a live switch requires the run "
                "operation, --mutation-mode live, and the owning host's guarded workflow"
            ),
        )
    )
    items.extend(consumer_surface_gates(scope, initial_reason))
    return items


def consumer_surface_gates(
    scope: dict[str, Any], reason: str | None = None
) -> list[dict[str, Any]]:
    return [
        gate(
            f"consumer:{host}:{surface}",
            phase="consumer-verification",
            required=True,
            reason=reason,
            command=[
                "nix",
                "eval",
                "--json",
                f".#fleetLifecycleConsumers.{host}.rendered.{surface}",
            ],
            applicability="applicable",
            expected_json=True,
            evidence_sha256=scope["consumerEvidence"][host][surface],
        )
        for host in scope["consumerHosts"]
        for surface in scope["consumerSurfaces"][host]
    ]


def stateful_gates(
    runtime_host: str, scope: dict[str, Any] | None = None
) -> list[dict[str, Any]]:
    wrapper = f"scripts/{runtime_host}/upgrade-{runtime_host}.sh"
    consumer_hosts = [] if scope is None else scope["consumerHosts"]
    other_consumer_hosts = [host for host in consumer_hosts if host != runtime_host]
    items = [
        gate(
            "readiness",
            phase="readiness",
            required=True,
            command=[wrapper, "check-upgrade-readiness"],
        ),
    ]
    items.extend(
        gate(
            f"build:{host}",
            phase="affected-host-build",
            required=True,
            command=["colmena", "build", "--on", host],
        )
        for host in other_consumer_hosts
    )
    if scope is not None:
        items.extend(consumer_surface_gates(scope))
    items.append(
        gate(
            "pre-change-backup",
            phase="pre-change-backup",
            required=True,
            command=[wrapper, "create-pre-upgrade-backup"],
        )
    )
    items.append(
        gate(
            f"dry-activate:{runtime_host}",
            phase="dry-activation",
            required=True,
            command=[wrapper, f"dry-activate-{runtime_host}"],
        )
    )
    items.extend(
        gate(
            f"dry-activate:{host}",
            phase="dry-activation",
            required=True,
            command=["colmena", "apply", "--on", host, "dry-activate"],
        )
        for host in other_consumer_hosts
    )
    items.append(
        gate(
            f"guarded-deployment:{runtime_host}",
            phase="guarded-deployment",
            required=True,
            command=[wrapper, f"deploy-{runtime_host}"],
        )
    )
    items.append(
        gate(
            f"owning-host-health:{runtime_host}",
            phase="live-verification",
            required=True,
            command=[wrapper, f"verify-{runtime_host}"],
        )
    )
    items.extend(
        gate(
            f"consumer-host-health:{host}",
            phase="live-verification",
            required=True,
            command=[
                f"scripts/{host}/test-{host.removesuffix('-vm')}-services.sh"
            ],
        )
        for host in other_consumer_hosts
    )
    items.append(
        gate(
            "backup-timer",
            phase="live-verification",
            required=True,
            reason="verified by the owning host's guarded verification workflow",
        )
    )
    items.append(
        gate(
            "snapshot",
            phase="live-verification",
            required=True,
            reason="verified by the owning host's guarded verification workflow",
        )
    )
    items.append(
        gate(
            "non-destructive-restore-check",
            phase="live-verification",
            required=True,
            reason="verified by the owning host's guarded verification workflow; no restore is run",
        )
    )
    return items


def manifest_verification_gate(
    gate_id: str,
    *,
    phase: str,
    check: dict[str, Any],
    reason: str | None = None,
    matches_gate: str | None = None,
) -> dict[str, Any]:
    return gate(
        gate_id,
        phase=phase,
        required=True,
        reason=reason,
        command=check["command"],
        expected_exit_codes=check.get("expectedExitCodes", [0]),
        expected_stdout=check.get("expectedStdout"),
        matches_gate=matches_gate,
    )


def removal_gates(
    runtime_host: str,
    scope: dict[str, Any],
    operation: str,
    service_class: str = "stateful",
) -> list[dict[str, Any]]:
    plan = scope["removalPlan"]
    plan_reason = (
        "plan operation reports required gates without executing them"
        if operation == "plan"
        else None
    )
    if service_class == "stateful":
        items = stateful_gates(runtime_host, scope)
    else:
        items = [
            gate(
                "static-validation",
                phase="static-validation",
                required=True,
                reason=plan_reason,
                command=["scripts/check.sh"],
                failure_classification="repository-wide",
            )
        ]
        items.extend(
            gate(
                f"build:{host}",
                phase="affected-host-build",
                required=True,
                reason=plan_reason,
                command=["colmena", "build", "--on", host],
            )
            for host in scope["affectedHosts"]
        )
        items.extend(consumer_surface_gates(scope, plan_reason))
        items.append(
            gate(
                "pre-change-backup",
                phase="pre-change-backup",
                required=False,
                status="not_applicable",
                reason="the removed service is stateless, so it has no restore-critical state",
            )
        )
        items.extend(
            gate(
                f"dry-activate:{host}",
                phase="dry-activation",
                required=True,
                reason=plan_reason,
                command=["colmena", "apply", "--on", host, "dry-activate"],
            )
            for host in scope["affectedHosts"]
        )
        items.extend(
            gate(
                f"guarded-deployment:{host}",
                phase="guarded-deployment",
                required=True,
                reason=plan_reason,
                command=["colmena", "apply", "--on", host, "switch"],
            )
            for host in scope["affectedHosts"]
        )
        items.append(
            gate(
                f"owning-host-health:{runtime_host}",
                phase="live-verification",
                required=True,
                reason=plan_reason,
                command=[
                    f"scripts/{runtime_host}/test-{runtime_host.removesuffix('-vm')}-services.sh"
                ],
            )
        )
        items.extend(
            gate(
                f"consumer-host-health:{host}",
                phase="live-verification",
                required=True,
                reason=plan_reason,
                command=[f"scripts/{host}/test-{host.removesuffix('-vm')}-services.sh"],
            )
            for host in scope["consumerHosts"]
            if host != runtime_host
        )

    pre_change_backup_index = next(
        index for index, item in enumerate(items) if item["id"] == "pre-change-backup"
    )
    retained_before = [
        manifest_verification_gate(
            f"retained-recovery-before:{check['id']}",
            phase="pre-change-recovery-proof",
            check=check,
            reason=plan_reason,
        )
        for check in plan.get("retainedRecoveryChecks", [])
    ]
    items[pre_change_backup_index + 1 : pre_change_backup_index + 1] = retained_before

    if service_class == "stateful":
        owner_deployment_index = next(
            index
            for index, item in enumerate(items)
            if item["id"] == f"guarded-deployment:{runtime_host}"
        )
        consumer_deployments = [
            gate(
                f"guarded-deployment:{host}",
                phase="guarded-deployment",
                required=True,
                reason=plan_reason,
                command=["colmena", "apply", "--on", host, "switch"],
            )
            for host in scope["consumerHosts"]
            if host != runtime_host
        ]
        items[owner_deployment_index + 1 : owner_deployment_index + 1] = consumer_deployments

    proof_items: list[dict[str, Any]] = []
    for surface in REMOVAL_SURFACES:
        section = plan["inventory"][surface]
        if "resources" not in section:
            proof_items.append(
                gate(
                    f"inventory-not-applicable:{surface}",
                    phase="live-removal-proof",
                    required=False,
                    status="not_applicable",
                    reason=section["notApplicableReason"],
                )
            )
            continue
        for resource in section["resources"]:
            disposition = "removed" if resource["disposition"] == "remove" else "retained"
            proof_items.append(
                manifest_verification_gate(
                    f"{disposition}:{surface}:{resource['id']}",
                    phase="live-removal-proof",
                    check=resource["verification"],
                    reason=plan_reason,
                )
            )
    proof_items.extend(
        manifest_verification_gate(
            f"surviving:{check['id']}",
            phase="surviving-service-proof",
            check=check,
            reason=plan_reason,
        )
        for check in plan["survivingServiceChecks"]
    )
    proof_items.extend(
        manifest_verification_gate(
            f"retained-recovery-after:{check['id']}",
            phase="post-change-recovery-proof",
            check=check,
            reason=plan_reason,
            matches_gate=f"retained-recovery-before:{check['id']}",
        )
        for check in plan.get("retainedRecoveryChecks", [])
    )
    if service_class == "stateful":
        proof_index = next(
            index for index, item in enumerate(items) if item["id"] == "backup-timer"
        )
    else:
        proof_index = len(items)
    items[proof_index:proof_index] = proof_items
    if plan_reason is not None:
        for item in items:
            if item["status"] == "not_run" and "reason" not in item:
                item["reason"] = plan_reason
    return items


def move_gates(scope: dict[str, Any]) -> list[dict[str, Any]]:
    source_host = scope["sourceHost"]
    target_host = scope["runtimeHost"]
    source_wrapper = f"scripts/{source_host}/upgrade-{source_host}.sh"
    target_wrapper = f"scripts/{target_host}/upgrade-{target_host}.sh"
    move = scope["movePlan"]
    verification_command = move["verificationCommand"]

    def proof_command(proof: str, *, recovery_point: bool = False) -> list[str]:
        command = [
            verification_command,
            proof,
            "--service",
            move["service"],
            "--source-host",
            source_host,
            "--target-host",
            target_host,
            "--state-boundary",
            move["stateBoundary"],
        ]
        if recovery_point:
            command.extend(
                ["--source-recovery-sha256", "{sourceRecoveryPointSha256}"]
            )
        return command

    def proof_gate(gate_id: str, proof: str, phase: str) -> dict[str, Any]:
        item = gate(
            gate_id,
            phase=phase,
            required=True,
            command=proof_command(proof, recovery_point=proof == "transfer"),
            expected_json=True,
        )
        item["sensitiveOutput"] = True
        return item
    other_consumer_hosts = [
        host
        for host in scope["consumerHosts"]
        if host not in (source_host, target_host)
    ]
    items = [
        gate(
            f"source-readiness:{source_host}",
            phase="readiness",
            required=True,
            command=[source_wrapper, "check-upgrade-readiness"],
        ),
        gate(
            f"target-readiness:{target_host}",
            phase="readiness",
            required=True,
            command=[target_wrapper, "check-upgrade-readiness"],
        ),
        proof_gate(
            f"target-secrets-permissions:{target_host}",
            "target-secrets-permissions",
            "readiness",
        ),
    ]
    items.extend(
        gate(
            f"build:{host}",
            phase="affected-host-build",
            required=True,
            command=["colmena", "build", "--on", host],
        )
        for host in other_consumer_hosts
    )
    items.extend(consumer_surface_gates(scope))
    items.extend(
        [
            gate(
                f"source-recovery-point:{source_host}",
                phase="pre-change-backup",
                required=True,
                command=[source_wrapper, "create-pre-upgrade-backup"],
            ),
            proof_gate(
                "transfer-evidence",
                "transfer",
                "state-transfer",
            ),
            gate(
                f"dry-activate:{target_host}",
                phase="dry-activation",
                required=True,
                command=[target_wrapper, f"dry-activate-{target_host}"],
            ),
            gate(
                f"dry-activate:{source_host}",
                phase="dry-activation",
                required=True,
                command=[source_wrapper, f"dry-activate-{source_host}"],
            ),
        ]
    )
    items.extend(
        gate(
            f"dry-activate:{host}",
            phase="dry-activation",
            required=True,
            command=["colmena", "apply", "--on", host, "dry-activate"],
        )
        for host in other_consumer_hosts
    )
    items.extend(
        [
            gate(
                f"guarded-deployment:{target_host}",
                phase="target-cutover",
                required=True,
                command=[target_wrapper, f"deploy-{target_host}"],
            ),
            gate(
                f"owning-host-health:{target_host}",
                phase="target-verification",
                required=True,
                command=[target_wrapper, f"verify-{target_host}"],
            ),
        ]
    )
    items.extend(
        gate(
            f"consumer-guarded-deployment:{host}",
            phase="consumer-cutover",
            required=True,
            command=[f"scripts/{host}/deploy-{host.removesuffix('-vm')}.sh"],
        )
        for host in other_consumer_hosts
    )
    items.extend(
        gate(
            f"consumer-deployment:{host}",
            phase="consumer-cutover",
            required=True,
            command=[f"scripts/{host}/deploy-{host.removesuffix('-vm')}.sh"],
        )
        for host in other_consumer_hosts
    )
    items.extend(
        gate(
            f"consumer-host-health:{host}",
            phase="consumer-verification",
            required=True,
            command=[f"scripts/{host}/test-{host.removesuffix('-vm')}-services.sh"],
        )
        for host in other_consumer_hosts
    )
    items.extend(
        [
            proof_gate(
                f"target-backup-recovery-ownership:{target_host}",
                "target-backup-recovery-ownership",
                "target-verification",
            ),
            gate(
                f"source-retirement:{source_host}",
                phase="source-retirement",
                required=True,
                command=[source_wrapper, f"deploy-{source_host}"],
            ),
            gate(
                f"source-retirement-health:{source_host}",
                phase="source-retirement",
                required=True,
                command=[source_wrapper, f"verify-{source_host}"],
            ),
        ]
    )
    for proof in (
        "old-runtime-absence",
        "old-listener-absence",
        "old-launcher-absence",
        "old-route-target-absence",
        "old-backup-responsibility-absence",
    ):
        items.append(
            proof_gate(
                f"{proof}:{source_host}",
                proof,
                "source-retirement-verification",
            )
        )
    return items


def mark_remaining_not_run(items: list[dict[str, Any]], start: int, failed_gate: str) -> None:
    for item in items[start:]:
        if item["status"] == "not_run" and "reason" not in item:
            item["reason"] = f"not run because required gate {failed_gate} did not pass"


def outcome_for(gates: list[dict[str, Any]]) -> str:
    incomplete_statuses = {"failed", "blocked", "not_run"}
    return (
        "incomplete"
        if any(item["required"] and item["status"] in incomplete_statuses for item in gates)
        else "complete"
    )


def repository_fingerprint(repo_root: Path) -> str:
    try:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_root,
            check=True,
            capture_output=True,
        ).stdout.strip()
        paths = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=repo_root,
            check=True,
            capture_output=True,
        ).stdout.split(b"\0")
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError("unable to fingerprint repository state with Git") from error

    digest = hashlib.sha256()
    digest.update(head)
    for raw_path in sorted(path for path in paths if path):
        relative_path = os.fsdecode(raw_path)
        path = repo_root / relative_path
        digest.update(b"\0path\0")
        digest.update(raw_path)
        if path.exists() or path.is_symlink():
            digest.update(f"\0mode\0{path.lstat().st_mode:o}".encode())
        if path.is_symlink():
            digest.update(b"\0symlink\0")
            digest.update(os.fsencode(os.readlink(path)))
        elif path.is_file():
            digest.update(b"\0file\0")
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            digest.update(b"\0missing\0")
    return digest.hexdigest()


def timestamp() -> str:
    return datetime.now(UTC).isoformat()


def receipt_filename(gate_id: str) -> str:
    return gate_id.replace(":", "-") + ".json"


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    temporary_path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary_path.replace(path)


def write_phase_receipt(
    item: dict[str, Any],
    *,
    receipt_dir: Path,
    scope: dict[str, Any],
    action: str,
    fingerprint: str,
) -> None:
    completed_at = timestamp()
    receipt: dict[str, Any] = {
        "schemaVersion": 1,
        "gateId": item["id"],
        "phase": item["phase"],
        "targetScope": scope,
        "lifecycleAction": action,
        "repositoryStateFingerprint": fingerprint,
        "completedAt": completed_at,
    }
    if "command" in item:
        receipt["delegatedCommand"] = item["command"]
    if "outputSha256" in item:
        receipt["outputSha256"] = item["outputSha256"]
    if "verificationEvidence" in item:
        receipt["verificationEvidence"] = item["verificationEvidence"]
    if (
        (item["id"] == "pre-change-backup" or item["id"].startswith("source-recovery-point:"))
        and "command" in item
    ):
        receipt["backupEvidence"] = {
            "delegatedCommand": item["command"],
            "completedAt": completed_at,
            "outputSha256": item["outputSha256"],
        }
    path = receipt_dir / receipt_filename(item["id"])
    write_json(path, receipt)
    item["receipt"] = str(path)


def write_run_manifest(
    path: Path,
    *,
    scope: dict[str, Any],
    action: str,
    service_class: str,
    fingerprint: str,
    completed_gate_ids: list[str],
) -> None:
    write_json(
        path,
        {
            "schemaVersion": 1,
            "targetScope": scope,
            "lifecycleAction": action,
            "serviceClass": service_class,
            "repositoryStateFingerprint": fingerprint,
            "completedGateIds": completed_gate_ids,
            "updatedAt": timestamp(),
        },
    )


def load_resume_manifest(
    manifest_path: Path,
    *,
    runtime_host: str,
    action: str,
    service_class: str,
    consumer_impact: str,
    fingerprint: str,
) -> dict[str, Any]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise RuntimeError(f"resume receipt is unavailable: {manifest_path}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError(f"resume receipt is invalid JSON: {manifest_path}") from error

    target_scope = manifest.get("targetScope", {})
    if (
        target_scope.get("runtimeHost") != runtime_host
        or target_scope.get("consumerImpact") != consumer_impact
        or manifest.get("lifecycleAction") != action
        or manifest.get("serviceClass") != service_class
    ):
        raise RuntimeError("resume receipt target scope or lifecycle classification changed")
    if manifest.get("repositoryStateFingerprint") != fingerprint:
        raise RuntimeError("resume receipt repository state fingerprint changed")

    if action == "move":
        expected_items = move_gates(target_scope)
    elif action == "removal":
        expected_items = removal_gates(runtime_host, target_scope, "run", service_class)
    else:
        expected_items = stateful_gates(runtime_host, target_scope)
    expected_gate_ids = [item["id"] for item in expected_items]
    completed_gate_ids = manifest.get("completedGateIds")
    if not isinstance(completed_gate_ids, list) or completed_gate_ids != expected_gate_ids[: len(completed_gate_ids)]:
        raise RuntimeError("resume phase receipts are not a contiguous completed phase prefix")
    for gate_id in completed_gate_ids:
        receipt_path = manifest_path.parent / receipt_filename(gate_id)
        try:
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError) as error:
            raise RuntimeError(f"resume phase receipt is unavailable or invalid: {receipt_path}") from error
        if (
            receipt.get("gateId") != gate_id
            or receipt.get("targetScope") != target_scope
            or receipt.get("lifecycleAction") != action
            or receipt.get("repositoryStateFingerprint") != fingerprint
            or not receipt.get("completedAt")
        ):
            raise RuntimeError(f"resume phase receipt does not match this run: {receipt_path}")
        if (
            (
                service_class == "stateful" and gate_id == "pre-change-backup"
            )
            or gate_id.startswith("source-recovery-point:")
        ) and not receipt.get("backupEvidence"):
            raise RuntimeError(f"resume phase receipt lacks mandatory backup evidence: {receipt_path}")
    return manifest


def run_stateful_workflow(
    items: list[dict[str, Any]],
    *,
    repo_root: Path,
    receipt_dir: Path,
    scope: dict[str, Any],
    action: str,
    service_class: str,
    fingerprint: str,
    completed_gate_ids: list[str],
) -> None:
    manifest_path = receipt_dir / "run.json"
    completed = set(completed_gate_ids)
    verification_passed = False
    verification_evidence: dict[str, Any] | None = None
    output_hashes: dict[str, str] = {}
    for index, item in enumerate(items):
        if item["id"] in completed:
            item["status"] = "passed"
            item["resumed"] = True
            item["receipt"] = str(receipt_dir / receipt_filename(item["id"]))
            receipt = json.loads(Path(item["receipt"]).read_text(encoding="utf-8"))
            if "outputSha256" in receipt:
                item["outputSha256"] = receipt["outputSha256"]
                output_hashes[item["id"]] = receipt["outputSha256"]
            if "matchesGate" in item and output_hashes.get(item["matchesGate"]) != item.get(
                "outputSha256"
            ):
                item["status"] = "failed"
                item["reason"] = "retained recovery evidence changed across the live switch"
                mark_remaining_not_run(items, index + 1, item["id"])
                break
            if item["id"].startswith(("owning-host-health:", "source-retirement-health:")):
                verification_passed = True
                verification_evidence = {
                    "delegatedCommand": item["command"],
                    "outputSha256": receipt["outputSha256"],
                }
            continue

        if item["status"] == "not_applicable":
            write_phase_receipt(
                item,
                receipt_dir=receipt_dir,
                scope=scope,
                action=action,
                fingerprint=fingerprint,
            )
            completed_gate_ids.append(item["id"])
            completed.add(item["id"])
            write_run_manifest(
                manifest_path,
                scope=scope,
                action=action,
                service_class=service_class,
                fingerprint=fingerprint,
                completed_gate_ids=completed_gate_ids,
            )
            continue

        if "command" in item:
            if "{sourceRecoveryPointSha256}" in item["command"]:
                recovery_hash = next(
                    (
                        value
                        for gate_id, value in output_hashes.items()
                        if gate_id.startswith("source-recovery-point:")
                    ),
                    None,
                )
                if recovery_hash is None:
                    item["status"] = "blocked"
                    item["reason"] = "fresh source recovery-point evidence is unavailable"
                    mark_remaining_not_run(items, index + 1, item["id"])
                    break
                item["command"] = [
                    recovery_hash if value == "{sourceRecoveryPointSha256}" else value
                    for value in item["command"]
                ]
            if not run_gate(
                item,
                cwd=repo_root,
                capture_output=(
                    item["id"] == "pre-change-backup"
                    or item["id"].startswith("source-recovery-point:")
                    or item["id"].startswith("target-secrets-permissions:")
                    or item["id"].startswith("owning-host-health:")
                    or item["id"].startswith("consumer-host-health:")
                    or item["id"].startswith("source-retirement-health:")
                ),
            ):
                mark_remaining_not_run(items, index + 1, item["id"])
                break
            if item["id"].startswith(("owning-host-health:", "source-retirement-health:")):
                verification_passed = True
                verification_evidence = {
                    "delegatedCommand": item["command"],
                    "outputSha256": item["outputSha256"],
                }
            if "outputSha256" in item:
                output_hashes[item["id"]] = item["outputSha256"]
            if "matchesGate" in item and output_hashes.get(item["matchesGate"]) != item.get(
                "outputSha256"
            ):
                item["status"] = "failed"
                item["reason"] = "retained recovery evidence changed across the live switch"
                mark_remaining_not_run(items, index + 1, item["id"])
                break
        elif verification_passed:
            item["status"] = "passed"
            item["verificationEvidence"] = verification_evidence
        else:
            item["status"] = "blocked"
            item["reason"] = "owning-host verification did not establish this evidence"
            mark_remaining_not_run(items, index + 1, item["id"])
            break

        write_phase_receipt(
            item,
            receipt_dir=receipt_dir,
            scope=scope,
            action=action,
            fingerprint=fingerprint,
        )
        completed_gate_ids.append(item["id"])
        completed.add(item["id"])
        write_run_manifest(
            manifest_path,
            scope=scope,
            action=action,
            service_class=service_class,
            fingerprint=fingerprint,
            completed_gate_ids=completed_gate_ids,
        )


def validate_receipt_dir(repo_root: Path, receipt_dir: Path) -> None:
    try:
        relative_path = receipt_dir.relative_to(repo_root)
    except ValueError:
        return
    if not relative_path.parts or relative_path.parts[0] != ".git":
        raise RuntimeError(
            "receipt directory must be outside the worktree or beneath the repository .git directory"
        )


def write_report(report: dict[str, Any], evidence_path: Path | None) -> None:
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if evidence_path is not None:
        write_json(evidence_path, report)
        print(f"Evidence: {evidence_path}", file=sys.stderr)
    print(rendered, end="")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plan, validate, or run a fleet production service lifecycle."
    )
    parser.add_argument("operation", choices=("plan", "validate", "run"))
    parser.add_argument(
        "--action", required=True, choices=("addition", "edit", "move", "removal", "upgrade")
    )
    parser.add_argument("--host", help="Owning runtime host from hosts.nix")
    parser.add_argument("--source-host", help="Current runtime owner for a move")
    parser.add_argument("--target-host", help="New runtime owner for a move")
    parser.add_argument("--service", help="Service identifier for move-specific proof")
    parser.add_argument(
        "--service-class", default="stateless", choices=("stateless", "stateful")
    )
    parser.add_argument(
        "--mutation-mode",
        default="none",
        choices=("none", "live"),
        help="Explicitly authorize the owner-scoped guarded live workflow",
    )
    parser.add_argument(
        "--consumer-impact",
        default="auto",
        choices=("auto", "generated", "host-local"),
        help="Override automatic generated-consumer applicability discovery",
    )
    parser.add_argument("--evidence", type=Path, help="Also write the structured report here")
    parser.add_argument("--receipt-dir", type=Path, help="Directory for resumable phase receipts")
    parser.add_argument("--resume", action="store_true", help="Resume matching completed phases")
    parser.add_argument(
        "--removal-manifest",
        type=Path,
        help="Structured removal inventory, disposition, and proof contract",
    )
    parser.add_argument(
        "--authorize-destruction",
        action="store_true",
        help="Explicitly authorize a manifest that destroys durable state or snapshots",
    )
    parser.add_argument(
        "--current-version-source", help="Declarative source of the deployed version"
    )
    parser.add_argument(
        "--target-version", help="Immutable package, image, input, or release target"
    )
    parser.add_argument(
        "--target-kind", choices=("flake-input", "image", "package", "source")
    )
    parser.add_argument(
        "--immutable-reference",
        help="OCI digest, locked revision, source hash, or Nix store reference",
    )
    parser.add_argument(
        "--migration-requirements",
        help="Required migrations, or an explicit none decision",
    )
    parser.add_argument(
        "--dependency-compatibility",
        help="Compatibility decision for service dependencies",
    )
    parser.add_argument("--downgrade-support", help="Upstream downgrade support decision")
    parser.add_argument("--intermediate-versions", help="Required intermediate releases, or explicit none")
    parser.add_argument("--configuration-rollback", help="Safe Nix generation rollback boundary")
    parser.add_argument("--data-rollback", help="Separate explicit snapshot/data recovery boundary")
    parser.add_argument("--state-boundary", help="Restore-critical state included in a move")
    parser.add_argument("--transfer-method", help="Explicit transfer or restore method for a move")
    parser.add_argument(
        "--move-verification-command",
        help="Read-only repo command used for service-specific move proofs",
    )
    parser.add_argument("--consistency-window", help="Source data consistency window for a move")
    parser.add_argument("--cutover-order", help="Operator-declared move cutover order")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help=argparse.SUPPRESS,
    )
    arguments = parser.parse_args()
    try:
        arguments.removal_plan = load_removal_plan(arguments)
    except ValueError as error:
        parser.error(str(error))
    if arguments.action == "move":
        required_decisions = {
            "--service": arguments.service,
            "--source-host": arguments.source_host,
            "--target-host": arguments.target_host,
            "--state-boundary": arguments.state_boundary,
            "--transfer-method": arguments.transfer_method,
            "--consistency-window": arguments.consistency_window,
            "--cutover-order": arguments.cutover_order,
            "--move-verification-command": arguments.move_verification_command,
        }
        missing = [
            name
            for name, value in required_decisions.items()
            if not value or not value.strip()
        ]
        if missing:
            parser.error(f"move requires explicit decisions: {', '.join(missing)}")
        if arguments.source_host == arguments.target_host:
            parser.error("move source and target owners must differ")
        if arguments.host is not None:
            parser.error("move uses --source-host and --target-host instead of --host")
        arguments.host = arguments.target_host
        if arguments.service_class != "stateful":
            parser.error("move currently requires --service-class stateful")
    elif not arguments.host:
        parser.error("--host is required unless --action move is selected")
    if arguments.action == "upgrade":
        required_decisions = {
            "--current-version-source": arguments.current_version_source,
            "--target-version": arguments.target_version,
            "--target-kind": arguments.target_kind,
            "--immutable-reference": arguments.immutable_reference,
            "--migration-requirements": arguments.migration_requirements,
            "--dependency-compatibility": arguments.dependency_compatibility,
            "--downgrade-support": arguments.downgrade_support,
            "--intermediate-versions": arguments.intermediate_versions,
            "--configuration-rollback": arguments.configuration_rollback,
            "--data-rollback": arguments.data_rollback,
        }
        missing = [
            name
            for name, value in required_decisions.items()
            if not value or not value.strip()
        ]
        if missing:
            parser.error(f"upgrade requires explicit decisions: {', '.join(missing)}")
        if not immutable_upgrade_target(
            arguments.target_version,
            arguments.target_kind,
            arguments.immutable_reference,
        ):
            parser.error(
                "upgrade target must include valid immutable evidence for its target kind"
            )
    if (
        arguments.operation == "run"
        and arguments.service_class != "stateful"
        and arguments.action != "removal"
    ):
        parser.error("run currently requires --service-class stateful")
    if (
        arguments.service_class == "stateful"
        and arguments.operation != "run"
        and not (
            arguments.action in ("move", "removal", "upgrade")
            and arguments.operation == "plan"
        )
    ):
        parser.error("stateful execution requires the run operation; upgrades may also be planned")
    if arguments.operation == "run" and arguments.mutation_mode != "live":
        parser.error("stateful run requires --mutation-mode live")
    if arguments.operation != "run" and arguments.mutation_mode != "none":
        parser.error("--mutation-mode live is valid only for the run operation")
    if arguments.resume and arguments.operation != "run":
        parser.error("--resume is valid only for the run operation")
    return arguments


def main() -> int:
    arguments = parse_arguments()
    selected_upgrade_plan = upgrade_plan(arguments)
    selected_move_plan = move_plan(arguments)
    selected_removal_plan = arguments.removal_plan
    repo_root = arguments.repo_root.resolve()
    consumer_impact, consumer_reason = resolve_consumer_impact(
        repo_root, arguments.host, arguments.action, arguments.consumer_impact
    )

    if arguments.operation == "run":
        receipt_dir = (
            arguments.receipt_dir.resolve()
            if arguments.receipt_dir
            else repo_root / ".git" / "fleet-lifecycle" / "current"
        )
        try:
            validate_receipt_dir(repo_root, receipt_dir)
            fingerprint = repository_fingerprint(repo_root)
            if arguments.resume:
                manifest = load_resume_manifest(
                    receipt_dir / "run.json",
                    runtime_host=arguments.host,
                    action=arguments.action,
                    service_class=arguments.service_class,
                    consumer_impact=consumer_impact,
                    fingerprint=fingerprint,
                )
                scope, scope_gate = discover_scope(
                    repo_root, arguments.host, consumer_impact, consumer_reason
                )
                enrich_scope(
                    scope,
                    arguments,
                    selected_upgrade_plan,
                    selected_move_plan,
                    selected_removal_plan,
                )
                if scope != manifest["targetScope"]:
                    raise RuntimeError("resume receipt target scope changed")
                completed_gate_ids = list(manifest.get("completedGateIds", []))
            else:
                scope, scope_gate = discover_scope(
                    repo_root, arguments.host, consumer_impact, consumer_reason
                )
                enrich_scope(
                    scope,
                    arguments,
                    selected_upgrade_plan,
                    selected_move_plan,
                    selected_removal_plan,
                )
                completed_gate_ids = []
        except RuntimeError as error:
            print(f"error: {error}", file=sys.stderr)
            return 2

        gates = [scope_gate]
        if scope is None:
            scope = {
                "runtimeHost": arguments.host,
                "consumerHosts": [],
                "consumerSurfaces": {},
                "consumerEvidence": {},
                "affectedHosts": [arguments.host],
                "consumerImpact": consumer_impact,
                "consumerReason": consumer_reason,
            }
            if selected_move_plan is not None:
                scope["sourceHost"] = arguments.source_host
                scope["movePlan"] = selected_move_plan
            if selected_removal_plan is not None:
                scope["removalPlan"] = selected_removal_plan
            if arguments.action == "move" and "movePlan" in scope:
                remaining = move_gates(scope)
            elif arguments.action == "removal" and "removalPlan" in scope:
                remaining = removal_gates(
                    arguments.host, scope, arguments.operation, arguments.service_class
                )
            else:
                remaining = stateful_gates(arguments.host, scope)
            mark_remaining_not_run(remaining, 0, "scope-discovery")
            gates.extend(remaining)
        else:
            print(f"Runtime owner: {scope['runtimeHost']}", file=sys.stderr)
            print(f"Consumer hosts: {', '.join(scope['consumerHosts']) or 'none'}", file=sys.stderr)
            if arguments.action == "move":
                remaining = move_gates(scope)
            elif arguments.action == "removal":
                remaining = removal_gates(
                    arguments.host, scope, arguments.operation, arguments.service_class
                )
            else:
                remaining = stateful_gates(arguments.host, scope)
            gates.extend(remaining)
            if not arguments.resume:
                write_run_manifest(
                    receipt_dir / "run.json",
                    scope=scope,
                    action=arguments.action,
                    service_class=arguments.service_class,
                    fingerprint=fingerprint,
                    completed_gate_ids=completed_gate_ids,
                )
            run_stateful_workflow(
                remaining,
                repo_root=repo_root,
                receipt_dir=receipt_dir,
                scope=scope,
                action=arguments.action,
                service_class=arguments.service_class,
                fingerprint=fingerprint,
                completed_gate_ids=completed_gate_ids,
            )
    else:
        scope, scope_gate = discover_scope(
            repo_root, arguments.host, consumer_impact, consumer_reason
        )
        enrich_scope(
            scope,
            arguments,
            selected_upgrade_plan,
            selected_move_plan,
            selected_removal_plan,
        )
        gates = [scope_gate]
        if scope is None:
            scope = {
                "runtimeHost": arguments.host,
                "consumerHosts": [],
                "consumerSurfaces": {},
                "consumerEvidence": {},
                "affectedHosts": [arguments.host],
                "consumerImpact": consumer_impact,
                "consumerReason": consumer_reason,
            }
            if selected_move_plan is not None:
                scope["sourceHost"] = arguments.source_host
                scope["movePlan"] = selected_move_plan
            if selected_removal_plan is not None:
                scope["removalPlan"] = selected_removal_plan
            if arguments.action == "move":
                remaining = move_gates(scope)
            elif arguments.action == "removal":
                remaining = removal_gates(
                    arguments.host, scope, arguments.operation, arguments.service_class
                )
            else:
                remaining = stateless_gates(scope, arguments.operation)
            mark_remaining_not_run(remaining, 0, "scope-discovery")
            gates.extend(remaining)
        else:
            print(f"Runtime owner: {scope['runtimeHost']}", file=sys.stderr)
            print(f"Consumer hosts: {', '.join(scope['consumerHosts']) or 'none'}", file=sys.stderr)
            print(f"Consumer impact: {consumer_impact} ({consumer_reason})", file=sys.stderr)
            if arguments.action == "move":
                remaining = move_gates(scope)
            elif arguments.action == "removal":
                remaining = removal_gates(
                    arguments.host, scope, arguments.operation, arguments.service_class
                )
            elif arguments.service_class == "stateful":
                remaining = stateful_gates(arguments.host, scope)
            else:
                remaining = stateless_gates(scope, arguments.operation)
            if arguments.operation == "plan":
                for item in remaining:
                    if item["status"] == "not_run" and "reason" not in item:
                        item["reason"] = "plan operation reports required gates without executing them"
            gates.extend(remaining)
            if arguments.operation == "validate":
                for index, item in enumerate(remaining):
                    if item["status"] == "not_applicable":
                        continue
                    if not run_gate(item, cwd=repo_root):
                        mark_remaining_not_run(remaining, index + 1, item["id"])
                        break

    report = {
        "schemaVersion": 2,
        "operation": arguments.operation,
        "action": arguments.action,
        "serviceClass": arguments.service_class,
        "mutationAllowed": arguments.mutation_mode == "live",
        "scope": scope,
        "gates": gates,
    }
    if selected_upgrade_plan is not None:
        report["upgradePlan"] = selected_upgrade_plan
        report["rollbackBoundaries"] = {
            "configuration": selected_upgrade_plan["configurationRollback"],
            "data": selected_upgrade_plan["dataRollback"],
        }
    if selected_move_plan is not None:
        report["movePlan"] = selected_move_plan
    if selected_removal_plan is not None:
        report["removalPlan"] = selected_removal_plan
    report["outcome"] = outcome_for(gates)
    write_report(report, arguments.evidence)
    return 0 if report["outcome"] == "complete" else 2


if __name__ == "__main__":
    raise SystemExit(main())
