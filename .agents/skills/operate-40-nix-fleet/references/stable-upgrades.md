# Stable Release Upgrades

Use this workflow for upgrade feasibility, stable upgrades, package bumps, OCI image updates, and flake-input changes.

## Establish the version source

Inspect evaluated configuration and live state when useful. Classify the service as a pinned nixpkgs package, explicit package override, OCI image tag plus digest, source-built derivation, or flake-input dependency. If the user asks only whether an upgrade is possible, answer feasibility and the required path before editing.

## Determine the stable target

Because release state changes, verify it live from primary sources: official releases or signed tags, changelog and migration guide, official registry metadata, then pinned nixpkgs behavior. Exclude prereleases and moving tags unless explicitly requested. Record the exact version and immutable digest or source hash.

## Build the compatibility case

Compare deployed and target versions. Identify intermediate upgrades, schema/config/data migrations, dependency floors, removed auth settings, changed health endpoints/ports/permissions/volumes, backup requirements, and downgrade support. Inspect every skipped release when upstream does not guarantee direct upgrades.

## Choose the repo change

- For nixpkgs software, determine whether `flake.lock` contains the target; update only the required input when practical and review the lock diff separately.
- For OCI services, keep an exact version and immutable digest. Never deploy a floating `stable` or `latest` tag alone.
- For source derivations, update version, source hash, dependency locks/hashes, patches, and tests together.
- Avoid changing unrelated services because a broad lock update exposes newer versions.

Update option defaults, runtime configuration, smoke expectations, and docs only where the release requires it.

## Prove before switching

1. Run formatting and static checks.
2. Run `nix flake check`.
3. Build the target host.
4. Dry-activate the target host.
5. For stateful services, create and verify a fresh consistent backup plus restore check.
6. State whether rollback means a Nix generation, application-supported downgrade, or explicit snapshot restore.

## Deploy and verify

Use `scripts/<host>/upgrade-<host>.sh run` when present. It must perform readiness and secret validation, pre-upgrade backup, dry activation, guarded deployment, and host verification. It deploys the reviewed repo state, must not silently update `flake.lock`, and must never auto-restore.

Confirm the running version/digest when observable, then verify local health, logs, migrations, login/auth, important reads and writes, routed endpoints, generated monitoring/Homepage state, fresh backup behavior, and restore validation. A healthy container and HTTP response do not prove a successful upgrade.

## Handle failure safely

- Diagnose before rollback; route or secret failures may not require reverting the app.
- Use Nix generation rollback only when the release has not made incompatible state changes.
- Restore data only as a separate, explicit recovery action from a selected snapshot.
- Preserve useful logs and migration evidence without exposing secrets.
- Report any manual upstream migration or admin-console step that prevents declarative completion.
