# Fleet Engineering Principles Blueprint

MediaVM defines the fleet standard: every service must be declarative,
reproducible, secure by default, upgradeable through guarded automation, and
recoverable from known-good state.

## Core Principles

- **Declare everything:** hosts, services, users, ports, mounts, timers, data
  paths, and recovery notes belong in Nix.
- **Keep one source of truth:** `hosts.nix`, `hosts/<name>/`, and
  `modules/<domain>/` define fleet reality.
- **Guard every change:** build, dry-activate, back up state where needed,
  deploy, then verify.
- **Recover by design:** stateful services must define their data root, backup
  policy, restore path, and restore validation.
- **Centralize app data:** app and service state belongs under
  `/srv/appsdata/<service_name>` so one restore-critical tree can be backed up
  consistently.
- **Keep secrets runtime-only:** secrets are encrypted in Git, decrypted only on
  authorized hosts, and consumed from runtime files.

## Automated Deployment Workflow

Fresh VM deployment follows a phased bootstrap model:

1. Authorize secrets by capturing the VM SSH host key, converting it to an age
   recipient, updating SOPS keys, and confirming decryption.
2. Confirm non-interactive SSH to the target host.
3. Prepare locally: enter `nix develop`; verify required tools, encrypted
   secrets, `nix flake check`, and host build.
4. Install the base VM externally. Destructive provisioning, such as
   `nixos-anywhere`, happens outside this fleet repo.
5. Deploy declarative state with the guarded Colmena switch for the host.
6. Restore app or service state from an explicit Restic snapshot when needed.
7. Verify hostname, mounts, services, backup timers, and restore checks.
8. See if the entire flow can be automated and done in a way that its easily resumable.

Use `nix develop`, then plain `colmena` commands or repo scripts. Prefer
`--on <host>`; use tags or full-fleet deploys only intentionally.

## Lifecycle And Upgrade Management

Upgrades deploy the current reviewed repo state. Review dependency and version
changes, including `flake.lock`, separately before running the upgrade.

Required upgrade sequence:

1. Readiness check: validate tools, secrets, SSH, `nix flake check`, and
   `colmena build --on <host>`.
2. Pre-upgrade backup: create and list a fresh backup for stateful services.
3. Dry activation: run `colmena apply --on <host> dry-activate`.
4. Guarded switch: deploy through the host's guarded workflow.
5. Post-upgrade verification: check hostname, service health, declared
   directories, backup timers, and restore validation.

Never auto-restore during an upgrade. Restore is a separate recovery action and
must use an explicit snapshot when multiple candidates exist.

## App Data And Backup Layout

MediaVM's appdata model is the fleet default for stateful services.

- Store persistent app and service data under `/srv/appsdata/<service_name>`.
- If an upstream app requires another data path, declare that path in Nix and
  use a symlink or bind mount so the authoritative data still lives cleanly
  under `/srv/appsdata/<service_name>`.
- Back up `/srv/appsdata` as the single Restic source for app and service
  state.
- Mount the backup SMB share at `/mnt/backups` using the shared
  `smb-credentials` secret and the fleet SMB mount pattern. `gateway-vm`
  currently uses `/mnt/backup` for its established Gateway state backup path;
  keep that exception explicit until it is intentionally migrated.
- Use the existing `restic-password` secret for Restic repositories; do not
  introduce service-specific Restic passwords unless there is a documented
  recovery reason.
- Keep Restic repositories, host names, tags, retention, restore checks, and
  recovery notes declared in Nix and aligned with the service module.

## Security And Secrets Standards

- Use SOPS plus `sops-nix` for all credentials, keys, password hashes, and
  service secrets.
- Each host decrypts secrets through an authorized age recipient derived from
  its SSH host key.
- Deployment must fail if the target host cannot decrypt required secrets.
- Keep plaintext secrets out of commits, logs, docs, shell history, generated
  configs, and chat.
- Provide an `example-secrets.yaml` shape with placeholders, and reject
  `CHANGE_ME` values during readiness checks.
- Consume secrets from `/run/secrets/*` or equivalent runtime paths.
- Use restrictive ownership and file modes for generated sensitive files.
- Open only required firewall ports; keep internal integration ports private
  unless explicitly exposed.

## Acceptance Standard For New Services

A new Gateway, Security, Identity, or future module is ready only when it:

- exposes options under `fleet.<domain>.<service>`;
- gates implementation with `mkIf cfg.enable`;
- declares users, groups, directories, ports, timers, mounts, and systemd
  dependencies in Nix;
- keeps persistent state under `/srv/appsdata/<service_name>`, with declared
  symlinks or bind mounts for apps that need legacy paths;
- documents required secrets and uses SOPS exclusively;
- includes guarded deploy and upgrade workflows when stateful or
  security-sensitive;
- defines backup, retention, restore, and restore-check behavior for persistent
  state;
- passes `nix flake check`, host build, dry activation, deployment, and service
  health checks;
- keeps README and host recovery notes aligned with operational reality.

## Operating Rule

If a service cannot be rebuilt, upgraded, secret-rotated, backed up, restored,
and verified through this pattern, it is not production-ready for the fleet.
