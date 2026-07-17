#!/usr/bin/env python3
"""Plan and validate a production service change without mutating production."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


STATUSES = ("passed", "failed", "blocked", "not_run", "not_applicable")
CONSUMER_TAG = "exposure-consumer"


def gate(
    gate_id: str,
    *,
    phase: str,
    required: bool,
    status: str = "not_run",
    reason: str | None = None,
    command: list[str] | None = None,
    exit_code: int | None = None,
) -> dict[str, Any]:
    if status not in STATUSES:
        raise ValueError(f"unsupported gate status: {status}")
    result: dict[str, Any] = {
        "id": gate_id,
        "phase": phase,
        "required": required,
        "status": status,
    }
    if reason is not None:
        result["reason"] = reason
    if command is not None:
        result["command"] = command
    if exit_code is not None:
        result["exitCode"] = exit_code
    return result


def run_gate(item: dict[str, Any], *, cwd: Path) -> bool:
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
        result = subprocess.run(
            command,
            cwd=cwd,
            check=False,
            stdout=sys.stderr,
            stderr=sys.stderr,
        )
    except OSError as error:
        item["status"] = "blocked"
        item["reason"] = f"unable to execute required command: {error.strerror or error}"
        return False
    item["exitCode"] = result.returncode
    if result.returncode == 0:
        item["status"] = "passed"
        return True
    item["status"] = "failed"
    item["reason"] = f"command exited with status {result.returncode}"
    return False


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
    }
    if any(path in generated_paths for path in paths):
        return "generated", "changed paths affect the generated exposure catalog"
    return "host-local", "changed paths do not affect a generated exposure surface"


def discover_scope(
    repo_root: Path, runtime_host: str, consumer_impact: str, consumer_reason: str
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    command = ["nix", "eval", "--json", "--file", str(repo_root / "hosts.nix")]
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
        item["reason"] = f"unable to evaluate host inventory: {error.strerror or error}"
        return None, item
    item["exitCode"] = result.returncode
    if result.returncode != 0:
        item["status"] = "failed"
        item["reason"] = f"host inventory evaluation exited with status {result.returncode}"
        return None, item

    try:
        hosts = json.loads(result.stdout)
    except json.JSONDecodeError:
        item["status"] = "failed"
        item["reason"] = "host inventory evaluation did not emit valid JSON"
        return None, item

    if runtime_host not in hosts:
        item["status"] = "failed"
        item["reason"] = f"owning host is absent from hosts.nix: {runtime_host}"
        return None, item

    consumer_hosts = (
        [
            name
            for name, host in hosts.items()
            if name != runtime_host and CONSUMER_TAG in host.get("tags", [])
        ]
        if consumer_impact == "generated"
        else []
    )
    scope = {
        "runtimeHost": runtime_host,
        "consumerHosts": consumer_hosts,
        "affectedHosts": [runtime_host, *consumer_hosts],
        "consumerImpact": consumer_impact,
        "consumerReason": consumer_reason,
    }
    item["status"] = "passed"
    return scope, item


def planned_gates(scope: dict[str, Any], operation: str) -> list[dict[str, Any]]:
    plan_reason = "plan operation reports required gates without executing them"
    initial_status = "not_run"
    initial_reason = plan_reason if operation == "plan" else None
    items = [
        gate(
            "static-validation",
            phase="static-validation",
            required=True,
            status=initial_status,
            reason=initial_reason,
            command=["scripts/check.sh"],
        )
    ]
    items.extend(
        gate(
            f"build:{host}",
            phase="affected-host-build",
            required=True,
            status=initial_status,
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
            status=initial_status,
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
                "this public command is non-mutating; a live switch requires separate explicit "
                "authorization and the owning host's guarded deployment workflow"
            ),
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


def write_report(report: dict[str, Any], evidence_path: Path | None) -> None:
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if evidence_path is not None:
        evidence_path.parent.mkdir(parents=True, exist_ok=True)
        evidence_path.write_text(rendered, encoding="utf-8")
        print(f"Evidence: {evidence_path}", file=sys.stderr)
    print(rendered, end="")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plan or validate a stateless fleet service change without live mutation."
    )
    parser.add_argument("operation", choices=("plan", "validate"))
    parser.add_argument("--action", required=True, choices=("addition", "edit"))
    parser.add_argument("--host", required=True, help="Owning runtime host from hosts.nix")
    parser.add_argument("--service-class", default="stateless", choices=("stateless",))
    parser.add_argument(
        "--consumer-impact",
        default="auto",
        choices=("auto", "generated", "host-local"),
        help="Override automatic generated-consumer applicability discovery",
    )
    parser.add_argument("--evidence", type=Path, help="Also write the structured report to this path")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    repo_root = arguments.repo_root.resolve()
    consumer_impact, consumer_reason = resolve_consumer_impact(
        repo_root, arguments.host, arguments.action, arguments.consumer_impact
    )
    scope, scope_gate = discover_scope(
        repo_root, arguments.host, consumer_impact, consumer_reason
    )
    gates = [scope_gate]

    if scope is None:
        scope = {
            "runtimeHost": arguments.host,
            "consumerHosts": [],
            "affectedHosts": [arguments.host],
            "consumerImpact": consumer_impact,
            "consumerReason": consumer_reason,
        }
        remaining = planned_gates(scope, arguments.operation)
        mark_remaining_not_run(remaining, 0, "scope-discovery")
        gates.extend(remaining)
    else:
        print(f"Runtime owner: {scope['runtimeHost']}", file=sys.stderr)
        print(f"Consumer hosts: {', '.join(scope['consumerHosts']) or 'none'}", file=sys.stderr)
        print(f"Consumer impact: {consumer_impact} ({consumer_reason})", file=sys.stderr)
        remaining = planned_gates(scope, arguments.operation)
        gates.extend(remaining)
        if arguments.operation == "validate":
            for index, item in enumerate(remaining):
                if item["status"] == "not_applicable":
                    continue
                if not run_gate(item, cwd=repo_root):
                    mark_remaining_not_run(remaining, index + 1, item["id"])
                    break

    report = {
        "schemaVersion": 1,
        "operation": arguments.operation,
        "action": arguments.action,
        "serviceClass": arguments.service_class,
        "mutationAllowed": False,
        "scope": scope,
        "gates": gates,
    }
    report["outcome"] = outcome_for(gates)
    write_report(report, arguments.evidence)
    return 0 if report["outcome"] == "complete" else 2


if __name__ == "__main__":
    raise SystemExit(main())
