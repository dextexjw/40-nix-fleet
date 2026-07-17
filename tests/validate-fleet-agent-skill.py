#!/usr/bin/env python3
"""Validate the repository-owned fleet operations skill."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


REQUIRED_ACTIONS = (
    "addition",
    "edit",
    "diagnosis",
    "move",
    "removal",
    "upgrade",
    "deployment",
    "recovery",
    "validation",
)
REQUIRED_REFERENCES = (
    "references/repo-surfaces.md",
    "references/validation-and-deployment.md",
    "references/stable-upgrades.md",
)


def require_phrases(text: str, phrases: tuple[str, ...], context: str) -> None:
    missing = [phrase for phrase in phrases if phrase not in text]
    if missing:
        raise AssertionError(f"{context}: {', '.join(missing)}")


def read(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"missing required file: {path}")
    return path.read_text(encoding="utf-8")


def validate_package(skill_dir: Path) -> str:
    skill_text = read(skill_dir / "SKILL.md")
    metadata_text = read(skill_dir / "agents/openai.yaml")

    frontmatter = re.match(r"\A---\n(.*?)\n---\n", skill_text, re.DOTALL)
    if frontmatter is None:
        raise AssertionError("SKILL.md must start with YAML frontmatter")

    header = frontmatter.group(1)
    if not re.search(r"^name:\s*operate-40-nix-fleet\s*$", header, re.MULTILINE):
        raise AssertionError("skill name must match its directory")
    description = re.search(r"^description:\s*(.+)$", header, re.MULTILINE)
    if description is None or len(description.group(1).strip()) < 40:
        raise AssertionError("skill description must explain its routing scope")

    for field in ("display_name", "short_description", "default_prompt"):
        if not re.search(rf"^\s*{field}:\s*.+$", metadata_text, re.MULTILINE):
            raise AssertionError(f"agents/openai.yaml is missing {field}")

    print("Skill package valid.")
    return skill_text


def validate_reference_links(skill_dir: Path, skill_text: str) -> None:
    linked_paths = re.findall(r"\[[^]]+\]\(([^)]+)\)", skill_text)
    for relative_path in REQUIRED_REFERENCES:
        if relative_path not in linked_paths:
            raise AssertionError(f"SKILL.md does not link required reference: {relative_path}")

    for relative_path in linked_paths:
        if "://" in relative_path or relative_path.startswith("#"):
            continue
        if not (skill_dir / relative_path).is_file():
            raise AssertionError(f"broken local reference in SKILL.md: {relative_path}")

    print("Reference links valid.")


def validate_lifecycle_scenarios(skill_dir: Path, skill_text: str) -> None:
    lowered = skill_text.lower()
    missing_actions = [action for action in REQUIRED_ACTIONS if action not in lowered]
    if missing_actions:
        raise AssertionError("missing lifecycle routing terms: " + ", ".join(missing_actions))

    scenario_contracts = {
        "investigation stays read-only": (
            "review, investigation, diagnosis, or upgrade feasibility",
            "do not mutate or deploy unless asked",
        ),
        "implementation selects guarded lifecycle": (
            "add, edit, remove, move, fix, deploy, or upgrade requests",
            "implement and verify the requested lifecycle stage",
        ),
        "incomplete gates block completion": (
            "failed, blocked, skipped, or not-run required gate",
            "outcome is incomplete",
        ),
        "existing host workflows remain authoritative": (
            "reuse existing guarded host workflows",
            "do not reimplement their behavior",
        ),
    }
    for scenario, required_phrases in scenario_contracts.items():
        require_phrases(lowered, required_phrases, f"scenario '{scenario}' lacks contract")

    router = skill_dir / "scripts/classify-lifecycle.py"
    read(router)
    scenarios = (
        ("Investigate why the routed endpoint is failing", "diagnosis", "investigation", False),
        ("Investigate why the deployment failed", "diagnosis", "investigation", False),
        ("Review the service removal plan", "diagnosis", "investigation", False),
        ("Diagnose the upgrade failure", "diagnosis", "investigation", False),
        ("Investigate whether we should move the service", "diagnosis", "investigation", False),
        ("Review the proposed fix before anyone applies it", "diagnosis", "investigation", False),
        ("Investigate whether this fix is safe", "diagnosis", "investigation", False),
        ("Diagnose this but do not fix it", "diagnosis", "investigation", False),
        ("Review this and do not make the change", "diagnosis", "investigation", False),
        ("Investigate only; do not implement changes", "diagnosis", "investigation", False),
        ("Diagnose and fix the routed endpoint", "edit", "implementation", True),
        ("Add a production service", "addition", "implementation", True),
        ("Edit the service configuration", "edit", "implementation", True),
        ("Move the service to media-vm", "move", "implementation", True),
        ("Remove the old service", "removal", "implementation", True),
        ("Upgrade the service to the stable release", "upgrade", "implementation", True),
        ("Deploy the reviewed service change", "deployment", "implementation", True),
        ("Recover service state from backup", "recovery", "recovery", False),
        ("Validate the testbed-vm service", "validation", "validation", False),
    )
    for request, action, mode, mutation_allowed in scenarios:
        result = subprocess.run(
            [sys.executable, str(router), request],
            check=True,
            capture_output=True,
            text=True,
        )
        routed = json.loads(result.stdout)
        expected = {
            "action": action,
            "mode": mode,
            "mutationAllowed": mutation_allowed,
        }
        observed = {key: routed[key] for key in expected}
        if observed != expected:
            raise AssertionError(
                f"request routing mismatch for {request!r}: expected {expected}, got {observed}"
            )

    print("Lifecycle scenario audit passed.")


def validate_repository_guidance(repo_root: Path) -> None:
    guidance = read(repo_root / "AGENTS.md").lower()
    required_guidance = (
        ".agents/skills/operate-40-nix-fleet/skill.md",
        "must use",
        "failed, blocked, skipped, or not-run required gate",
        "outcome is incomplete",
    )
    require_phrases(guidance, required_guidance, "AGENTS.md does not enforce the fleet skill")

    duplicate_paths = [
        path
        for path in repo_root.glob("**/operate-40-nix-fleet/SKILL.md")
        if path.parent != repo_root / ".agents/skills/operate-40-nix-fleet"
    ]
    if duplicate_paths:
        raise AssertionError(
            "duplicate repository skill packages: " + ", ".join(map(str, duplicate_paths))
        )

    print("Repository skill guidance valid.")


def validate_supported_setup(skill_dir: Path) -> None:
    setup = skill_dir / "scripts/link-user-skill.sh"
    read(setup)

    with tempfile.TemporaryDirectory() as temporary_directory:
        codex_home = Path(temporary_directory) / "codex"
        duplicate = codex_home / "skills/operate-40-nix-fleet"
        duplicate.mkdir(parents=True)
        (duplicate / "SKILL.md").write_text("duplicate", encoding="utf-8")
        environment = os.environ | {"CODEX_HOME": str(codex_home)}
        command = ["bash", str(setup), "--repo-skill", str(skill_dir)]

        check_result = subprocess.run(
            [*command, "--check"],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        if check_result.returncode == 0:
            raise AssertionError("setup check accepted an ambiguous user-scoped copy")

        subprocess.run([*command, "--install"], check=True, env=environment)
        if not duplicate.is_symlink() or duplicate.resolve() != skill_dir.resolve():
            raise AssertionError("setup did not replace the duplicate with a canonical symlink")
        backups = list((codex_home / "skill-backups").glob("operate-40-nix-fleet-*"))
        if len(backups) != 1:
            raise AssertionError("setup did not preserve exactly one disabled backup copy")

    print("Supported skill setup valid.")


def main() -> int:
    default_repo_root = Path(__file__).resolve().parents[1]
    skill_dir = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else default_repo_root / ".agents/skills/operate-40-nix-fleet"
    )
    repo_root = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else default_repo_root

    try:
        skill_text = validate_package(skill_dir)
        validate_reference_links(skill_dir, skill_text)
        validate_lifecycle_scenarios(skill_dir, skill_text)
        validate_repository_guidance(repo_root)
        validate_supported_setup(skill_dir)
    except AssertionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
