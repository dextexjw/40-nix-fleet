# Repository Surfaces

Use this map to discover the current implementation. Do not assume every service needs every surface; inspect the nearest working peer in the same domain.

## Core sources of truth

| Concern | Inspect first | Update when applicable |
| --- | --- | --- |
| Policy | `AGENTS.md`, `PRINCIPLES.md` | Usually read-only |
| Fleet inventory | `hosts.nix`, `hosts/common.nix` | New host, address, tags, deployment target |
| Host ownership | `hosts/<host>/configuration.nix`, `hosts/<host>/README.md` | Enablement, secrets, mounts, operator workflow |
| Domain composition | `modules/<domain>/default.nix`, `common.nix` | Service-module import and shared behavior |
| Public options | `modules/<domain>/options.nix` | Ports, images, state paths, feature knobs |
| Service runtime | `modules/<domain>/services/<service>.nix` or domain module | Units, containers, users, state, dependencies |
| Exposure | `modules/<domain>/catalog.nix`, `hosts/<host>/exposure.nix`, `lib/exposure.nix` | Route, Homepage, auth, Checkmate, TCP, smoke |
| Network policy | `modules/<domain>/firewall.nix`, catalog-derived consumers | Required backend/listener ports only |
| Secrets | `.sops.yaml`, `secrets/example-secrets.yaml`, `secrets/secrets.yaml`, `scripts/lib/required-secrets.sh`, host `sops.secrets` | Secret or consumer changes |
| Backup/recovery | `modules/<domain>/backup.nix`, `recovery-notes.nix`, `scripts/<host>/create-*backup.sh`, `restore-*.sh` | Stateful service, consistency, or restore changes |
| Validation | `scripts/check.sh`, `scripts/<host>/test-*.sh`, `deploy-*.sh`, `upgrade-*.sh` | Health, capability, route, backup, upgrade behavior |
| Operator docs | root README, host README, generated recovery notes | Ownership, URLs, lifecycle, backup, restore changes |

## New-service completeness scan

Search the closest service identifier across the repo, then account for:

1. Import and option definition.
2. Runtime module and owning-host enablement.
3. Persistent and temporary storage, identities, tmpfiles, mounts, and permissions.
4. HTTP/TCP port and firewall reachability restricted to intended callers.
5. Catalog route, Homepage card, auth mode, OIDC metadata, Checkmate target, and smoke definition.
6. Secret encryption regex, encrypted document shape, example placeholder, required-host manifest, host declaration, runtime ownership, and restart units.
7. Backup source, database dump or quiescing behavior, restore stop/start lists, restore check, retention, and recovery notes.
8. Host smoke tests, local health, public/internal route, generated consumers, and runtime-gated capability checks.
9. Root and host documentation.

## Auth and exposure choices

- Reuse `native-oidc` when the app supports trustworthy OIDC. Add Authentik provisioning metadata and keep the client secret in `/run/secrets`.
- Reuse `forward-auth` for apps without suitable native OIDC, then validate unauthenticated redirect behavior and an app-local health endpoint.
- Use no auth only when the service is deliberately private or implements an accepted auth boundary.
- Define non-HTTP services through catalog `tcpRoute` so generated Gateway listeners and firewall rules remain authoritative.
- Treat both Gateway nodes as consumers when shared exposure, Authentik, Homepage, DNS, TLS, or generated routing changes.

## Storage and recovery choices

- Put restore-critical state under `/srv/appsdata/<service>`.
- Keep large replaceable payloads on the appropriate media/NAS mount only after confirming that boundary with the user.
- Keep temporary or incomplete data outside Restic when safe to recreate.
- Record external state such as Garage/S3 ownership in recovery notes even when another host backs it up.
- Add stateful units to consistency-first backup and restore stop/start handling. Verify parent traversal and runtime UID/GID permissions.

## Removal scan

Run `rg -n -i '<service>|<unit>|<port>|<hostname>|<secret-prefix>'` and inspect generated-consumer code. Remove only unshared entries. Check domain imports/options, host config, catalog consumers, firewall, proxy listeners, backup and restore lists, SOPS surfaces, docs, and smoke scripts.
