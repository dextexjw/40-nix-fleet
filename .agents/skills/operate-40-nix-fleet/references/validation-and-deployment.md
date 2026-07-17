# Validation And Deployment

Apply the narrowest complete ladder. Run live actions only when the request authorizes deployment or recovery.

## Development shell

Enter the repository shell once with `nix develop`. Run subsequent `sops`, `nix`, `colmena`, and repo-script commands plainly from that shell.

## Pre-edit and static checks

1. Capture `git status --short --branch` and the relevant diff boundary.
2. Use `rg` to identify all affected consumers.
3. Run `git diff --check` after edits.
4. Format changed Nix files with repo `nixfmt`; use `nixfmt --check` for check-only work.
5. Run `bash -n` on changed shell scripts.
6. Use `scripts/check.sh` for the broad repository gate when scope and time permit.

## Secrets validation

When secrets or their manifests change:

1. Work inside `nix develop`.
2. Edit `secrets/secrets.yaml` with SOPS; never transform ciphertext with generic YAML tooling.
3. Synchronize `.sops.yaml`, `secrets/example-secrets.yaml`, `scripts/lib/required-secrets.sh`, and host declarations.
4. Verify `sops --decrypt secrets/secrets.yaml >/dev/null`.
5. Run `scripts/lib/required-secrets.sh validate-manifest "$PWD"` or `scripts/check.sh`.
6. Use the host deploy/upgrade wrapper to confirm the target age recipient and reject placeholders or empty required values.

Never print decrypted content merely to prove validation.

## Evaluation and activation ladder

Run in order for each affected host:

```bash
nix flake check
colmena build --on <host>
colmena apply --on <host> dry-activate
```

Direct `colmena apply --on <host> switch` is the repository-standard deployment command. Use a host's guarded deploy or upgrade wrapper when that host or lifecycle requires its additional readiness, backup, or verification phases.

New files referenced by a flake may be invisible until tracked in Git. Do not stage unrelated files. If staging is not authorized, report the evaluation limitation rather than broadening the Git operation.

## Stateful change gate

Before a version change, migration, ownership move, or risky stateful edit:

1. Confirm backup mount and credentials.
2. Use `scripts/<host>/create-<host-or-domain>-backup.sh` or the matching guarded upgrade phase.
3. Confirm a fresh tagged Restic snapshot and a successful non-destructive restore check.
4. Record state outside that repository.
5. Do not restore automatically if deployment fails. Diagnose first, then require explicit restore authority and snapshot selection.

## Post-switch proof

Prove applicable layers:

1. Correct host identity and mounts.
2. Expected systemd unit/container state, restart count, and recent logs.
3. Runtime user access to required state paths.
4. Local/backend health and expected response semantics.
5. Public/internal route behavior, including redirects/auth status.
6. Runtime capability or provider state when secret-gated.
7. Rendered Homepage, Authentik, Traefik/DNS/TLS, and Checkmate state on every consumer.
8. Backup timer, fresh backup, restore check, and snapshot listing.
9. Unrelated critical services remain healthy.

Prefer `scripts/<host>/test-*.sh` as the executable acceptance test, then add targeted checks for uncovered behavior.

## Removal proof

After switching the owner and consumers, verify no runtime, listener, generated consumer entry, route, or stale backup/restore reference remains. Prove surviving services and shared generators stay healthy.

## Failure reporting

Classify each failure as caused by the requested change, pre-existing/concurrent, environmental, or a live operational blocker. Provide the failed command, concise evidence, completion impact, and safest next action. A required gate that failed, was blocked, or was not run keeps the outcome incomplete.
