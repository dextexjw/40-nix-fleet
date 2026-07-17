#!/usr/bin/env python3
"""Mechanically reject unmistakable fleet lifecycle bypass commands."""

from __future__ import annotations

import json
import re
import sys


SNAPSHOT_ID = re.compile(r"^[0-9a-fA-F]{8,64}$")
RESTORE_SCRIPT = re.compile(r"(?:^|\s)scripts/[^\s]+/restore-[^\s]+\.sh(?:\s+([^\s;&|]+))?")
SECRET_FILE = re.compile(r"(?:^|[\s'\"])(?:\./)?secrets/secrets\.yaml(?:$|[\s'\"])" )


def deny(reason: str, safe_path: str) -> int:
    print(f"blocked: {reason}. Safe path: {safe_path}", file=sys.stderr)
    return 2


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "")
    except (AttributeError, json.JSONDecodeError):
        return deny("invalid Bash hook input", "retry with a valid command")
    if not isinstance(command, str):
        return deny("Bash command is not text", "retry with a valid command")

    if re.search(r"\bcolmena\s+apply\s+(?:--[^\s]+\s+)*switch\b", command) and not re.search(
        r"\b--on(?:=|\s+)\S+", command
    ):
        return deny(
            "direct unscoped whole-fleet switch is not authorized",
            "use the guarded host lifecycle or colmena apply --on <host> switch",
        )

    if SECRET_FILE.search(command):
        first_command = re.sub(r"^(?:\s*(?:nix\s+develop\s+--command\s+)?)", "", command)
        sops_aware = first_command.startswith("sops ")
        decrypt_requested = "--decrypt" in command or re.search(
            r"(?:^|\s)-[A-Za-z]*d[A-Za-z]*(?:\s|$)", command
        )
        decrypt_is_silent = not decrypt_requested or re.search(
            r">\s*/dev/null(?:\s|$)", command
        )
        if not sops_aware or not decrypt_is_silent:
            return deny(
                "generic editing or plaintext output of the encrypted production secret file is unsafe",
                "use a SOPS-aware edit, or validate with sops --decrypt secrets/secrets.yaml >/dev/null",
            )

    if re.search(r"\brestic\s+restore\s+(?:latest|\$?\{?[^\s}]*latest[^\s}]*\}?)\b", command):
        return deny(
            "automatic or implicit Restic snapshot selection is not authorized",
            "use an approved recovery workflow with an explicit snapshot ID",
        )
    for match in RESTORE_SCRIPT.finditer(command):
        snapshot = match.group(1)
        if snapshot is None or not SNAPSHOT_ID.fullmatch(snapshot.strip("'\"")):
            return deny(
                "restore workflow lacks an explicit snapshot selection",
                "obtain approval and rerun the recovery script with an explicit snapshot ID",
            )

    if re.search(r"(?:^|[\s;&|])(?:sudo\s+)?nixos-anywhere(?:\s|$)", command):
        return deny(
            "destructive machine provisioning is outside the fleet lifecycle",
            "use the separately authorized external provisioning workflow",
        )
    if re.search(
        r"\brm\s+(?:-[^\s]*r[^\s]*f|-[^\s]*f[^\s]*r)\s+(?:--\s+)?['\"]?/srv/appsdata(?:/|['\"]?(?:\s|$))",
        command,
    ):
        return deny(
            "unapproved deletion of restore-critical appdata is destructive",
            "use declarative removal, record state disposition, and obtain explicit destruction authority",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
