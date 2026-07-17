---
name: operate-40-nix-fleet
description: Operate the complete production service lifecycle in this 40-nix-fleet checkout using its declarative Nix, Colmena, SOPS, exposure-catalog, backup, restore, and verification patterns. Use for a fleet service addition, edit, diagnosis, move, removal, upgrade, deployment, recovery, or validation; a service version or image change; Gateway, Homepage, Authentik/OIDC, Checkmate, secrets, storage, or backup wiring; or any production service change governed by PRINCIPLES.md.
---

# Operate 40 Nix Fleet

Treat the checkout as the source of truth and `PRINCIPLES.md` as the production contract. Carry authorized implementation through proportionate validation and live proof. Do not mistake healthy evaluation for a healthy service.

## Establish scope

1. Confirm the working directory and read the applicable `AGENTS.md` plus `PRINCIPLES.md` completely.
2. Inspect `git status --short --branch` before editing. Preserve unrelated changes and identify shared files another rollout may own.
3. Classify the request:
   - For review, investigation, diagnosis, or upgrade feasibility, inspect and report first. Do not mutate or deploy unless asked.
   - For add, edit, remove, move, fix, deploy, or upgrade requests, implement and verify the requested lifecycle stage.
   - For recovery requests, diagnose first and require explicit authority before restore, snapshot selection, state deletion, or other destructive action.
   - For validation requests, run only the requested safe gates unless live mutation is explicitly authorized.
   - Treat “complete the deployment workflow” or an approved concrete rollout as authorization for the guarded implementation and validation it describes. Mentioning `PRINCIPLES.md` alone does not authorize mutation.
   - When intent is ambiguous, run `scripts/classify-lifecycle.py '<request>'` and keep its safe read-only default unless the user clearly authorizes implementation.
4. Identify every affected host: runtime owner, both Gateway consumers when shared exposure changes, Homepage/Auth consumers, monitoring, backup owner, and any old owner during a move or removal.
5. Read the target host README, host config, domain `default.nix`, `options.nix`, `catalog.nix`, one closest service module, and host deploy/upgrade/test scripts.

Read [references/repo-surfaces.md](references/repo-surfaces.md) before adding, removing, moving, or changing cross-host behavior. Read [references/validation-and-deployment.md](references/validation-and-deployment.md) before any live switch or recovery action. Read [references/stable-upgrades.md](references/stable-upgrades.md) for every version, package, image, flake-input, or “latest stable” request.

## Make design decisions from evidence

1. Prefer the closest working repo pattern over a generic upstream deployment example.
2. Decide explicitly:
   - native NixOS module/package versus OCI container;
   - runtime host and ownership;
   - native OIDC, forward-auth, or no auth;
   - HTTP route, catalog `tcpRoute`, or host-local access only;
   - durable state, large replaceable payloads, temporary data, and external object storage;
   - secrets and which hosts consume each secret;
   - backup consistency, restore procedure, retention, and rollback limits.
3. Default restore-critical state to `/srv/appsdata/<service>`. Ask before choosing a boundary when durable state is mixed with large downloaded or reproducible payloads.
4. Keep secrets encrypted in Git and runtime-only on hosts. Never expose decrypted values in logs, diffs, docs, or chat.
5. Pin releases reproducibly. Do not introduce a floating `latest` or `stable` tag as the deployed artifact.

## Execute the lifecycle

### Add a service

1. Research only upstream runtime facts the repo pattern does not answer: supported stable release, configuration, health endpoint, persistence, migration, authentication, and dependencies.
2. Add and import the service module. Extend domain options only when the setting belongs to the host stack's public contract.
3. Declare identities, directories, permissions, units or containers, dependencies, ports, and health behavior in Nix. Minimize capabilities and firewall exposure.
4. Add catalog routes, Homepage, auth, Checkmate, TCP exposure, and generated smoke metadata as applicable.
5. Enable the service from the owning host and declare SOPS files with restrictive ownership and restart behavior.
6. Synchronize every secret surface and edit encrypted secrets only with SOPS from the development shell.
7. Integrate backup consistency, restore handling, non-destructive restore checks, recovery notes, host README, root fleet map, and host smoke tests as applicable.
8. Validate every generated consumer, not only the app host.

### Edit or diagnose a service

1. Trace the service identifier, option, unit/container, port, data path, secrets, catalog entry, route, monitors, backup scripts, and docs with `rg` before changing code.
2. For a reported fault, reproduce and inspect live app or runtime state before patching. Distinguish app failure, dependency failure, generated-config drift, secret gating, routing, DNS, TLS, auth, and client mismatch.
3. When a fix is authorized, patch the declarative cause and the durable workflow that allowed recurrence. Avoid leaving a manual host-only fix as the final state.
4. Expand smoke coverage when existing checks could pass while the feature remained broken.
5. Re-run target-specific proof plus affected consumer-host proof.

### Move a service

1. Treat the change as an ownership migration: new runtime, storage transfer or restore, secrets, route backend, monitoring, Homepage/Auth, backups, docs, and old runtime retirement.
2. Define cutover order and the data-consistency window before switching. Take a fresh source backup for stateful services.
3. Prove the new owner and route, then prove the old unit, launcher, route target, and backup responsibility are absent or intentionally dormant.

### Remove a service

1. Inventory all references before deletion. Decide whether state and snapshots are retained, exported, or destroyed; never infer permission to delete durable data or backups.
2. Remove module imports/options, host enablement, catalog exposure, firewall/listeners, SOPS declarations and manifests, backup/restore service lists, smoke checks, monitors, generated recovery notes, and docs when no longer shared.
3. Deploy the runtime owner and every generated consumer host.
4. Prove live absence: no unit/container/listener, Homepage/Auth/Checkmate entry, generated route, or former app response. Prove unrelated surviving services remain healthy.

### Upgrade a service

1. Determine feasibility before editing. Identify whether the target is an app package, OCI image, Nix package override, or flake-input change.
2. Verify the stable release and migration path from official upstream sources. Inspect breaking changes, intermediate versions, database/storage migrations, dependency floors, downgrade support, and image architecture.
3. Update the smallest reproducible pin and required configuration. Keep `flake.lock` changes deliberate and separately reviewable.
4. Update tests, docs, and recovery assumptions changed by the release.
5. For stateful services, run the guarded upgrade workflow: readiness, fresh consistent backup, dry activation, guarded switch, and post-upgrade verification. Never auto-restore.
6. Treat Nix generation rollback and data rollback as separate operations. Do not run an old binary against irreversibly migrated data without upstream support or an explicit snapshot restore plan.

## Validate in layers

Reuse existing guarded host workflows and do not reimplement their behavior. Use host scripts and the ordered gates in [references/validation-and-deployment.md](references/validation-and-deployment.md). At minimum for a production service change:

1. Check formatting, shell syntax, secret manifests, and flake evaluation.
2. Build affected hosts and dry-activate them.
3. Create a verified pre-change backup when state or migration risk exists.
4. Switch through the guarded host workflow when deployment is requested.
5. Verify unit/container state, local and routed health, auth/capabilities, generated Homepage and monitoring state, backup timer, fresh snapshot, and restore check as applicable.
6. Report commands, affected hosts, evidence, and unrelated or unresolved failures.

A failed, blocked, skipped, or not-run required gate means the outcome is incomplete. Mark a gate not applicable only with a concrete reason. Never claim completion from partial validation.

## Guardrails

- Enter `nix develop` and use plain `colmena` commands from that shell. Do not teach one-shot `nix develop -c colmena ...` as the standard workflow.
- Prefer `colmena ... --on <host>`. Use tags or a whole-fleet switch only when intentionally requested.
- Stage newly created Nix files only when evaluation requires Git visibility and staging is within the requested workflow; otherwise explain the blocker.
- Never manually reorder or rewrite SOPS ciphertext. Use SOPS-aware editing and verify decryption without printing plaintext.
- Never auto-restore, guess a snapshot when several exist, delete appdata, rotate a Restic password, or perform destructive provisioning without explicit authority.
- Separate target-service failures from unrelated dirty-tree or broad-smoke failures; preserve both in the handoff.
- Keep host README and generated recovery notes aligned whenever operator behavior changes.

For Codex installations that also scan `$CODEX_HOME/skills`, run `scripts/link-user-skill.sh --check` to detect an ambiguous user-scoped copy or `scripts/link-user-skill.sh --install` to preserve that copy outside discovery and link the user path to this package.
