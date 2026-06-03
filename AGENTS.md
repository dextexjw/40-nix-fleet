# Repository Guidelines

Fleet is managed as a Nix flake and deployed with Colmena, so changes should always keep host reproducibility front of mind. Use this guide to stay consistent with the existing configuration style.

`PRINCIPLES.md` is the mandatory service blueprint. Apply it when adding or changing production services, especially guarded deployment, upgrade, security, secrets, backup, restore, and verification standards.

## Fleet Engineering Principles
- Treat MediaVM as the reference architecture for production services.
- Prefer declarative, reproducible Nix over manual VM state.
- Keep host inventory, service modules, secrets shape, and recovery notes as the source of truth.
- Design every service to be safely deployed, upgraded, verified, and rolled back or restored.
- Keep secrets encrypted in Git and runtime-only on hosts; never place plaintext secrets in code, docs, logs, or generated configs.
- Minimize network exposure and declare only the ports, users, permissions, and dependencies a service actually needs.
- For stateful or security-sensitive services, include backup, restore, guarded deployment, and post-deploy validation from the start.

## Project Structure & Module Organization
- `flake.nix` wires external inputs and exposes the Colmena hive plus the development shell.
- `hosts.nix` is the single inventory; per-host configs live in `hosts/<name>/` alongside hardware profiles and shared logic in `hosts/common.nix`.
- Service modules are grouped under `modules/<domain>/` and exposed via the `fleet.<domain>.<service>` option namespace (e.g. `modules/dev/gitea.nix`).
- Keep assets such as TLS material inside the relevant module options (`fleet.security.*`) rather than committing secrets.

## Build, Test, and Development Commands
- Use one deployment workflow: enter the dev shell with `nix develop`, then run plain `colmena` commands from that shell.
- Do not document or prefer one-shot deployment commands such as `nix develop -c colmena ...`; they are harder to standardise and troubleshoot.
- `nix flake check` ensures all modules evaluate and option contracts stay valid.
- `colmena build --on <host>` builds a single host without switching it.
- `colmena apply --on <host> dry-activate` validates a single host activation plan without switching state.
- `colmena apply --on <host> switch` is the standard deployment command; for example, `colmena apply --on media-vm switch`.
- Use `colmena apply --on @<tag> switch` only when intentionally deploying a host group defined in `hosts.nix`, and use `colmena apply switch` only when intentionally deploying the whole fleet.

## Coding Style & Naming Conventions
- Use two-space indentation and keep attribute sets alphabetised where practical.
- Follow the existing section banners (`# ===`) and organise modules as `options` then `config`.
- Name options `fleet.<domain>.<service>` and expose user-tunable settings through `mkOption` with informative defaults.
- Prefer descriptive attribute keys (`domain`, `port`, `description`) and consistent casing for hostnames and routes.

## Testing Guidelines
- Extend or adjust modules under `modules/` and rerun `nix flake check` before review.
- For behavioural changes, exercise `colmena apply --on <host> dry-activate` to confirm activations succeed.
- For `media-vm` changes touching the media stack, SMB mounts, SOPS secrets, or Restic, deploy with `colmena apply --on media-vm switch` and run `scripts/media-vm/test-media-backup.sh` from the development shell. This starts `appsdata-backup.service`, runs `appsdata-restore-check.service`, verifies `appsdata-backup.timer`, and lists the latest tagged snapshots.
- Keep `README.md` and the generated `/etc/fleet/media-vm.md` recovery notes in sync when backup or restore procedures change.
- Capture any manual verification (e.g. Grafana reachable on port 3000) in the pull request notes so reviewers can mirror the checks.

## Commit & Pull Request Guidelines
- Match the existing history of short, lower-case imperative summaries (e.g. `adding reverse proxy`).
- Each PR should explain the motivation, list affected hosts or services, and call out required secrets or DNS updates.
- Include screenshots or command transcripts when modifying user-facing dashboards or endpoints.
- Reference related issues or host tags for traceability, and ensure CI/CD or deployment checks are linked before requesting review.
