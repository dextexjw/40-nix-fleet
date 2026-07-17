#!/usr/bin/env python3
"""Run the canonical production service lifecycle and emit structured evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


STATUSES = ("passed", "failed", "blocked", "not_run", "not_applicable")


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
        should_capture = capture_output or "expectedJson" in item
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
        sys.stderr.buffer.write(stdout)
        sys.stderr.buffer.write(stderr)
        sys.stderr.flush()
        item["outputSha256"] = hashlib.sha256(stdout + stderr).hexdigest()
    if result.returncode != 0:
        item["status"] = "failed"
        item["reason"] = f"command exited with status {result.returncode}"
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
    if action == "addition":
        return "generated", "service additions are validated against generated fleet consumers"

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
    if item["id"] == "pre-change-backup":
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

    expected_gate_ids = [
        item["id"] for item in stateful_gates(runtime_host, target_scope)
    ]
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
        if gate_id == "pre-change-backup" and not receipt.get("backupEvidence"):
            raise RuntimeError(f"resume phase receipt lacks mandatory backup evidence: {receipt_path}")
    return manifest


def run_stateful_workflow(
    items: list[dict[str, Any]],
    *,
    repo_root: Path,
    receipt_dir: Path,
    scope: dict[str, Any],
    action: str,
    fingerprint: str,
    completed_gate_ids: list[str],
) -> None:
    manifest_path = receipt_dir / "run.json"
    completed = set(completed_gate_ids)
    verification_passed = False
    verification_evidence: dict[str, Any] | None = None
    for index, item in enumerate(items):
        if item["id"] in completed:
            item["status"] = "passed"
            item["resumed"] = True
            item["receipt"] = str(receipt_dir / receipt_filename(item["id"]))
            if item["id"].startswith("owning-host-health:"):
                verification_passed = True
                receipt = json.loads(Path(item["receipt"]).read_text(encoding="utf-8"))
                verification_evidence = {
                    "delegatedCommand": item["command"],
                    "outputSha256": receipt["outputSha256"],
                }
            continue

        if "command" in item:
            if not run_gate(
                item,
                cwd=repo_root,
                capture_output=(
                    item["id"] == "pre-change-backup"
                    or item["id"].startswith("owning-host-health:")
                    or item["id"].startswith("consumer-host-health:")
                ),
            ):
                mark_remaining_not_run(items, index + 1, item["id"])
                break
            if item["id"].startswith("owning-host-health:"):
                verification_passed = True
                verification_evidence = {
                    "delegatedCommand": item["command"],
                    "outputSha256": item["outputSha256"],
                }
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
            service_class="stateful",
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
    parser.add_argument("--action", required=True, choices=("addition", "edit"))
    parser.add_argument("--host", required=True, help="Owning runtime host from hosts.nix")
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
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help=argparse.SUPPRESS,
    )
    arguments = parser.parse_args()
    if arguments.operation == "run" and arguments.service_class != "stateful":
        parser.error("run currently requires --service-class stateful")
    if arguments.service_class == "stateful" and arguments.operation != "run":
        parser.error("stateful execution requires the run operation")
    if arguments.operation == "run" and arguments.mutation_mode != "live":
        parser.error("stateful run requires --mutation-mode live")
    if arguments.operation != "run" and arguments.mutation_mode != "none":
        parser.error("--mutation-mode live is valid only for the run operation")
    if arguments.resume and arguments.operation != "run":
        parser.error("--resume is valid only for the run operation")
    return arguments


def main() -> int:
    arguments = parse_arguments()
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
                if scope != manifest["targetScope"]:
                    raise RuntimeError("resume receipt target scope changed")
                completed_gate_ids = list(manifest.get("completedGateIds", []))
            else:
                scope, scope_gate = discover_scope(
                    repo_root, arguments.host, consumer_impact, consumer_reason
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
            remaining = stateful_gates(arguments.host, scope)
            mark_remaining_not_run(remaining, 0, "scope-discovery")
            gates.extend(remaining)
        else:
            print(f"Runtime owner: {scope['runtimeHost']}", file=sys.stderr)
            print(f"Consumer hosts: {', '.join(scope['consumerHosts']) or 'none'}", file=sys.stderr)
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
                fingerprint=fingerprint,
                completed_gate_ids=completed_gate_ids,
            )
    else:
        scope, scope_gate = discover_scope(
            repo_root, arguments.host, consumer_impact, consumer_reason
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
            remaining = stateless_gates(scope, arguments.operation)
            mark_remaining_not_run(remaining, 0, "scope-discovery")
            gates.extend(remaining)
        else:
            print(f"Runtime owner: {scope['runtimeHost']}", file=sys.stderr)
            print(f"Consumer hosts: {', '.join(scope['consumerHosts']) or 'none'}", file=sys.stderr)
            print(f"Consumer impact: {consumer_impact} ({consumer_reason})", file=sys.stderr)
            remaining = stateless_gates(scope, arguments.operation)
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
    report["outcome"] = outcome_for(gates)
    write_report(report, arguments.evidence)
    return 0 if report["outcome"] == "complete" else 2


if __name__ == "__main__":
    raise SystemExit(main())
