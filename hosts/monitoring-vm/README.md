# monitoring-vm

`monitoring-vm` runs Checkmate, Beszel Hub, ntfy notifications, fleet
monitoring agents, appdata backups, and restore checks.

Fleet inventory lives in `../../hosts.nix`. Host configuration lives in
`configuration.nix` and imports the monitoring stack plus Checkmate
provisioning modules from `../../modules/monitoring/`.

## Host Model

Important host values:

- FQDN: `monitoring-vm.home.arpa`
- IP: `10.2.20.115`
- Gateway: `10.2.20.1`
- DNS: `10.2.20.1`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`
- VM RAM: `8 GB`
- VM CPU cores: `2`
- Backup SMB share: `//nas.home.arpa/backups` mounted at `/mnt/backups`

Application state lives under `/srv/appsdata`, which is the restore-critical
path backed up by Restic.

## Service Access

| Service | Canonical route | Alias | Backend |
| --- | --- | --- | --- |
| Checkmate | `https://checkmate.jax22.com` | `http://checkmate.h` | `10.2.20.115:52345` |
| Beszel | `https://beszel.jax22.com` | `http://beszel.h` | `10.2.20.115:8090` |
| ntfy | `https://ntfy.jax22.com` | `http://ntfy.h` | `10.2.20.115:2586` |
| Checkmate Capture | direct agent API only | none | `10.2.20.115:59232` |
| Beszel Agent | direct agent API only | none | `10.2.20.115:45876` |

Traefik routes and Homepage cards are declared on the Gateway nodes from
`hosts/monitoring-vm/exposure.nix`.

## State Paths

Important appdata paths:

- `/srv/appsdata/beszel-hub`
- `/srv/appsdata/checkmate`
- `/srv/appsdata/checkmate/mongo`
- `/srv/appsdata/checkmate/uploads`
- `/srv/appsdata/ntfy`

Checkmate MongoDB and ntfy are stopped during the automatic Restic backup so
the repository captures consistent service state.

## Secrets

Required shared secrets:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`

Required monitoring secrets:

- `checkmate-environment`, containing `JWT_SECRET=...`
- `checkmate-capture-environment`, containing `API_SECRET=...`
- `checkmate-provisioning-credentials`, containing `CHECKMATE_EMAIL=...` and `CHECKMATE_PASSWORD=...`
- `beszel-agent-key`, containing the Beszel Hub public key
- `beszel-agent-token`, reserved for Beszel universal-token registration
- `beszel-oidc-client-secret`, shared with Authentik for Beszel native OIDC

`checkmate-provisioning-credentials` must reference an existing Checkmate admin
or superadmin account. The bootstrap, deploy, and upgrade wrappers reject
`CHANGE_ME` placeholders before switching the host.

Beszel agents run in listener mode by default with the hub public key from
`beszel-agent-key`. Set `fleet.monitoring.agents.beszel.hubUrl` and
`fleet.monitoring.agents.beszel.tokenFile` only after a hub-owned universal
token is generated.

Beszel Hub uses Authentik as a native OIDC provider. Authentik provisions the
provider and application on `gateway-vm`; `beszel-hub-oidc-config.service`
patches Beszel's PocketBase `users` collection before the hub starts. The
redirect URI is `https://beszel.jax22.com/api/oauth2-redirect`. Local password
login remains enabled unless
`fleet.monitoring.stack.beszel.oidc.disablePasswordAuth` is set.

ntfy is served through Gateway at `https://ntfy.jax22.com` and keeps its
auth/cache/attachment state under `/srv/appsdata/ntfy`. Mobile push forwarding
depends on the server `base-url` staying `https://ntfy.jax22.com` and
`upstream-base-url` staying `https://ntfy.sh`.

Normal edit flow:

```sh
nix develop
sops secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

`monitoring-vm` decrypts secrets using `/etc/ssh/ssh_host_ed25519_key`. After a
new VM install or host key change, capture the host recipient:

```sh
ssh smoke@10.2.20.115 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

Add the printed `age1...` recipient to `.sops.yaml`, then rekey:

```sh
sops updatekeys secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

Keep `restic-password` stable. It is the encryption key for the Restic
repository; changing it makes existing snapshots unreadable with the new value.

## Bootstrap

Use this flow after preparing a fresh `monitoring-vm` install. The destructive
VM install is handled outside this fleet repo.

```sh
nix develop
scripts/monitoring-vm/bootstrap-monitoring-vm.sh run
```

The bootstrap phases are resumable:

- `check-local-readiness`: verifies tools, encrypted secrets, `nix flake check`, and `colmena build --on monitoring-vm`.
- `enable-vm-secret-access`: captures the VM SSH host key, adds the age recipient to `.sops.yaml`, and runs `sops updatekeys`.
- `dry-activate-monitoring-vm`: validates the activation plan with `colmena apply --on monitoring-vm dry-activate`.
- `deploy-monitoring-vm`: runs the guarded deployment.
- `restore-appdata`: restores existing appdata from Restic when a matching snapshot exists.
- `verify-monitoring-vm`: verifies service health, routes, backup, and restore validation.

## Upgrade

Use this flow for an already-running `monitoring-vm`. It deploys the current
repo state only; update and review `flake.lock` separately before running it.

```sh
nix develop
scripts/monitoring-vm/upgrade-monitoring-vm.sh run
```

The upgrade workflow checks readiness, creates a pre-upgrade backup, dry
activates, deploys, and verifies services. It never restores appdata
automatically.

## Deploy

Use plain Colmena commands from inside `nix develop`.

```sh
colmena build --on monitoring-vm
colmena apply --on monitoring-vm dry-activate
colmena apply --on monitoring-vm switch
```

The guarded deploy helper checks local SOPS decryption and confirms the VM has
a matching SOPS recipient before switching:

```sh
scripts/monitoring-vm/deploy-monitoring.sh
```

## Checkmate Provisioning

Checkmate monitors are declared from the fleet exposure catalog and generated
into `/etc/fleet/checkmate-targets.json`.

- Service: `checkmate-provisioning.service`
- Target file: `/etc/fleet/checkmate-targets.json`
- Last run summary: `/var/lib/checkmate-provisioning/last-summary.json`
- Managed identity: `fleet-declared` plus `fleet-service:<id>` or `fleet-host:<host>`
- Expected managed monitors: `41`
- Service route monitors: `37`
- Host hardware monitors: `4`

Service HTTP monitors use the real routed `https://*.jax22.com` hostnames.
`monitoring-vm` declares those names in `/etc/hosts` to point at `gateway-vm`
so Checkmate can reach Traefik with the expected SNI and route hostnames.
The ntfy backend firewall allows both `gateway-vm` and `gateway2-vm`.
Hardware monitors target each Capture agent's `/api/v1/metrics` endpoint.

The provisioning service creates missing managed monitors, patches changed
managed monitors, resumes managed monitors that became active again, and pauses
stale managed monitors. It never deletes stale monitors, preserving Checkmate
history.

Beszel provisioning is intentionally out of scope. Beszel Hub and agents still
run normally, but Beszel systems are not managed by the Checkmate provisioning
service. OIDC provider configuration is handled separately by
`beszel-hub-oidc-config.service`.

## Backups and Restore

`monitoring-vm` backs up `/srv/appsdata` with Restic.

- Service: `monitoring-appdata-backup.service`
- Timer: `monitoring-appdata-backup.timer`
- Source: `/srv/appsdata`
- Repository: `/mnt/backups/restic/appdata/monitoring-vm`
- Password file: `/run/secrets/restic-password`
- Restic host: `monitoring-vm`
- Restic tag: `appsdata`
- Non-destructive restore validation: `monitoring-appdata-restore-check.service`

Recommended consistency-first manual backup:

```sh
scripts/monitoring-vm/create-monitoring-backup.sh
```

Post-deploy validation:

```sh
scripts/monitoring-vm/test-monitoring-services.sh
```

Destructive restore outline:

1. Deploy `monitoring-vm` once to create users, secrets, mounts, and units.
2. Stop the backup timer and monitoring services, including `ntfy-sh.service`.
3. Mount `/mnt/backups`.
4. Choose a `monitoring-vm` appdata snapshot ID.
5. Restore the snapshot to `/` with `restic --verify`.
6. Run `systemd-tmpfiles --create`.
7. Restart Beszel Hub, Checkmate MongoDB, Checkmate, ntfy, and the backup timer.
