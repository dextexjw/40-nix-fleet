#!/usr/bin/env python3
"""Classify a fleet request without granting implicit live authority."""

from __future__ import annotations

import json
import re
import sys


def contains(text: str, *terms: str) -> bool:
    return any(re.search(rf"\b{re.escape(term)}\b", text) for term in terms)


def classify(request: str) -> dict[str, str | bool]:
    text = request.casefold()

    if contains(text, "recover", "recovery", "restore"):
        return {"action": "recovery", "mode": "recovery", "mutationAllowed": False}

    if contains(text, "upgrade") and any(
        phrase in text for phrase in ("can we", "could we", "is it possible", "feasibility")
    ):
        return {"action": "upgrade", "mode": "investigation", "mutationAllowed": False}

    denies_mutation = bool(
        re.search(
            r"\b(?:do not|don't|never|without)\b.*"
            r"\b(?:fix|implement|deploy|apply|change|move|remove|upgrade|go ahead)\b",
            text,
        )
        or re.search(r"\bread[ -]only\b|\bonly investigate\b", text)
    )
    if denies_mutation:
        if contains(text, "validate", "validation", "check", "test"):
            return {"action": "validation", "mode": "validation", "mutationAllowed": False}
        return {"action": "diagnosis", "mode": "investigation", "mutationAllowed": False}

    investigation_intent = contains(
        text, "diagnose", "diagnosis", "debug", "investigate", "review", "why"
    )
    explicit_implementation = bool(
        re.search(
            r"\b(?:and|then)\s+"
            r"(?:fix|implement|deploy|apply|change|move|remove|upgrade)\b",
            text,
        )
        or re.search(r"\b(?:go ahead|make the change|apply the change|carry it out)\b", text)
    )
    if investigation_intent and not explicit_implementation:
        return {"action": "diagnosis", "mode": "investigation", "mutationAllowed": False}

    implementation_routes = (
        (("add", "addition"), "addition"),
        (("move", "migrate"), "move"),
        (("remove", "removal", "retire"), "removal"),
        (("upgrade", "bump"), "upgrade"),
        (("deploy", "deployment", "rollout", "switch"), "deployment"),
        (("edit", "change", "configure", "fix", "implement"), "edit"),
    )
    for terms, action in implementation_routes:
        if contains(text, *terms):
            return {"action": action, "mode": "implementation", "mutationAllowed": True}

    if contains(text, "validate", "validation", "check", "test"):
        return {"action": "validation", "mode": "validation", "mutationAllowed": False}

    return {"action": "unknown", "mode": "investigation", "mutationAllowed": False}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} REQUEST", file=sys.stderr)
        return 2
    print(json.dumps(classify(sys.argv[1]), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
