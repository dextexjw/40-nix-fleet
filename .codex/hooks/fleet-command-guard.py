#!/usr/bin/env python3
"""Mechanically reject unmistakable fleet lifecycle bypass commands."""

from __future__ import annotations

import json
import re
import shlex
import sys


SNAPSHOT_ID = re.compile(r"^[0-9a-fA-F]{8,64}$")
SECRET_FILE = re.compile(
    r"(?:^|[\s'\"])(?:\./)?secrets/secrets\.yaml(?:$|[\s'\"])"
)


def deny(reason: str, safe_path: str) -> int:
    print(f"blocked: {reason}. Safe path: {safe_path}", file=sys.stderr)
    return 2


def command_segments(command: str) -> list[str]:
    return [
        segment.strip()
        for segment in re.split(r"(?:&&|\|\||[;|])", command)
        if segment.strip()
    ]


def command_tokens(segment: str) -> list[str]:
    try:
        return shlex.split(segment)
    except ValueError:
        return segment.split()


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "")
    except (AttributeError, json.JSONDecodeError):
        return deny("invalid Bash hook input", "retry with a valid command")
    if not isinstance(command, str):
        return deny("Bash command is not text", "retry with a valid command")

    for segment in command_segments(command):
        arguments = command_tokens(segment)
        basenames = [argument.rsplit("/", 1)[-1] for argument in arguments]

        if "colmena" in basenames:
            colmena_index = basenames.index("colmena")
            colmena_arguments = arguments[colmena_index + 1 :]
            if "apply" in colmena_arguments and "switch" in colmena_arguments:
                host_scoped = "--on" in colmena_arguments or any(
                    argument.startswith("--on=") and len(argument) > len("--on=")
                    for argument in colmena_arguments
                )
                if not host_scoped:
                    return deny(
                        "direct unscoped whole-fleet switch is not authorized",
                        "use the guarded host lifecycle or colmena apply --on <host> switch",
                    )

        if SECRET_FILE.search(segment):
            sops_index = basenames.index("sops") if "sops" in basenames else -1
            sops_aware = sops_index >= 0
            sops_arguments = arguments[sops_index + 1 :] if sops_aware else []
            decrypt_requested = (
                "decrypt" in sops_arguments
                or "--decrypt" in sops_arguments
                or any(
                    re.fullmatch(r"-[A-Za-z]*d[A-Za-z]*", argument)
                    for argument in sops_arguments
                )
            )
            decrypt_is_silent = not decrypt_requested or re.search(
                r">\s*/dev/null(?:\s|$)", segment
            )
            if not sops_aware or not decrypt_is_silent:
                return deny(
                    "generic editing or plaintext output of the encrypted production secret file is unsafe",
                    "use a SOPS-aware edit, or validate with sops --decrypt secrets/secrets.yaml >/dev/null",
                )

        if "restic" in basenames:
            restic_index = basenames.index("restic")
            restic_arguments = arguments[restic_index + 1 :]
            if "restore" in restic_arguments:
                restore_arguments = restic_arguments[
                    restic_arguments.index("restore") + 1 :
                ]
                if "latest" in restore_arguments:
                    return deny(
                        "automatic or implicit Restic snapshot selection is not authorized",
                        "use an approved recovery workflow with an explicit snapshot ID",
                    )

        for index, argument in enumerate(arguments):
            if not re.fullmatch(
                r"(?:\./)?scripts/[^\s]+/restore-[^\s]+\.sh", argument
            ):
                continue
            snapshot = arguments[index + 1] if index + 1 < len(arguments) else None
            if snapshot is None or not SNAPSHOT_ID.fullmatch(snapshot):
                return deny(
                    "restore workflow lacks an explicit snapshot selection",
                    "obtain approval and rerun the recovery script with an explicit snapshot ID",
                )

        if "nixos-anywhere" in basenames:
            return deny(
                "destructive machine provisioning is outside the fleet lifecycle",
                "use the separately authorized external provisioning workflow",
            )
        if "rm" in basenames:
            rm_index = basenames.index("rm")
            if any(
                argument == "/srv/appsdata" or argument.startswith("/srv/appsdata/")
                for argument in arguments[rm_index + 1 :]
            ):
                return deny(
                    "unapproved deletion of restore-critical appdata is destructive",
                    "use declarative removal, record state disposition, and obtain explicit destruction authority",
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
