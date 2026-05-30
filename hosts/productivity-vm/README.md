# productivity-vm

`productivity-vm` runs the personal productivity stack, nginx-backed internal
apps, Git forges, standalone Garage and RustFS object storage, PostgreSQL,
appdata backups, and restore checks.

Fleet inventory lives in `../../hosts.nix`. Host configuration lives in
`configuration.nix` and imports the stack from
`../../modules/productivity/stack.nix`.

## Host Model

Important host values:

- FQDN: `productivity-vm.home.arpa`
- IP: `10.2.20.114`
- Gateway: `10.2.20.1`
- DNS: `10.2.20.1`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`
- VM RAM: `8 GB`
- VM CPU cores: `4`
- Backup SMB share: `//nas.home.arpa/backups` mounted at `/mnt/backups`

Application state lives under `/srv/appsdata`, which is the restore-critical
path backed up by Restic.

## Service Access

| Service | Route | Backend |
| --- | --- | --- |
| Gitea | `http://gitea.h` | `10.2.20.114:3000` |
| Forgejo | `http://forgejo.h` | `10.2.20.114:3002` |
| Material for MkDocs | `http://docs.h` | `10.2.20.114:80` |
| Paperless-ngx | `http://paperless.h` | `10.2.20.114:80` |
| FreshRSS | `http://freshrss.h` | `10.2.20.114:80` |
| SearXNG | `http://searxng.h` | `10.2.20.114:8087` |
| PrivateBin | `http://privatebin.h` | `10.2.20.114:80` |
| Vaultwarden | `http://vaultwarden.h` | `10.2.20.114:8222` |
| Syncthing | `http://syncthing.h` | `10.2.20.114:8384` |
| Stirling PDF | `http://stirling-pdf.h` | `10.2.20.114:8086` |
| Firefly III | `http://firefly.h` | `10.2.20.114:80` |
| Nextcloud | `http://nextcloud.h` | `10.2.20.114:80` |
| Garage S3 API | `http://garage.h` | `10.2.20.114:3900` |
| Garage static web | `http://garage-web.h` | `10.2.20.114:3902` |
| RustFS S3 API | `http://rustfs.h` | `10.2.20.114:9000` |
| RustFS console | `http://rustfs-console.h` | `10.2.20.114:9001` |
| ntfy | `http://ntfy.h` | `10.2.20.114:2586` |

Traefik routes and Homepage cards are declared on `gateway-vm`.

## State Paths

Important appdata paths:

- `/srv/appsdata/gitea`
- `/srv/appsdata/forgejo`
- `/srv/appsdata/mkdocs`
- `/srv/appsdata/paperless`
- `/srv/appsdata/freshrss`
- `/srv/appsdata/privatebin`
- `/srv/appsdata/firefly-iii`
- `/srv/appsdata/nextcloud`
- `/srv/appsdata/vaultwarden`
- `/srv/appsdata/syncthing`
- `/srv/appsdata/stirling-pdf`
- `/srv/appsdata/garage`
- `/srv/appsdata/rustfs`
- `/srv/appsdata/ntfy`
- `/srv/appsdata/postgresql`
- `/srv/appsdata/postgresql-dumps`

`productivity-postgresql-dump.service` writes
`/srv/appsdata/postgresql-dumps/latest.sql.gz` before Restic backups.

## Secrets

Required shared secrets:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`

Required productivity secrets:

- `firefly-app-key`
- `freshrss-admin-password`
- `garage-admin-token`
- `garage-metrics-token`
- `garage-rpc-secret`
- `nextcloud-admin-password`
- `paperless-admin-password`
- `rustfs-environment`
- `searxng-environment`
- `syncthing-gui-password`
- `vaultwarden-environment`

Normal edit flow:

```sh
nix develop
sops secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

`productivity-vm` decrypts secrets using `/etc/ssh/ssh_host_ed25519_key`.
After a new VM install or host key change, capture the host recipient:

```sh
ssh smoke@10.2.20.114 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

Add the printed `age1...` recipient to `.sops.yaml`, then rekey:

```sh
sops updatekeys secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

Keep `restic-password` stable. It is the encryption key for the Restic
repository; changing it makes existing snapshots unreadable with the new value.

## Bootstrap

Use this flow after preparing a fresh `productivity-vm` install. The
destructive VM install is handled outside this fleet repo.

```sh
nix develop
scripts/productivity-vm/bootstrap-productivity-vm.sh run
```

The bootstrap phases are resumable:

- `check-local-readiness`: verifies tools, encrypted secrets, `nix flake check`, and `colmena build --on productivity-vm`.
- `enable-vm-secret-access`: captures the VM SSH host key, adds the age recipient to `.sops.yaml`, and runs `sops updatekeys`.
- `dry-activate-productivity-vm`: validates the activation plan with `colmena apply --on productivity-vm dry-activate`.
- `deploy-productivity-vm`: runs the guarded deployment.
- `restore-appdata`: restores existing appdata from Restic when a matching snapshot exists.
- `initialize-garage`: assigns the single Garage node to the `productivity` zone with `20G` capacity when no role exists.
- `verify-productivity-vm`: verifies service health, routes, backup, and restore validation.

## Upgrade

Use this flow for an already-running `productivity-vm`. It deploys the current
repo state only; update and review `flake.lock` separately before running it.

```sh
nix develop
scripts/productivity-vm/upgrade-productivity-vm.sh run
```

The upgrade workflow checks readiness, creates a pre-upgrade backup, dry
activates, deploys, initializes the Garage layout when needed, and verifies
services. It never restores appdata automatically.

## Deploy

Use plain Colmena commands from inside `nix develop`.

```sh
colmena build --on productivity-vm
colmena apply --on productivity-vm dry-activate
colmena apply --on productivity-vm switch
```

The guarded deploy helper checks local SOPS decryption and confirms the VM has
a matching SOPS recipient before switching:

```sh
scripts/productivity-vm/deploy-productivity.sh
```

## Backups and Restore

`productivity-vm` backs up `/srv/appsdata` with Restic.

- Service: `productivity-appdata-backup.service`
- Timer: `productivity-appdata-backup.timer`
- Source: `/srv/appsdata`
- Repository: `/mnt/backups/restic/appdata/productivity-vm`
- Password file: `/run/secrets/restic-password`
- Restic host: `productivity-vm`
- Restic tag: `appsdata`
- Non-destructive restore validation: `productivity-appdata-restore-check.service`

Recommended consistency-first manual backup:

```sh
scripts/productivity-vm/create-productivity-backup.sh
```

Post-deploy validation:

```sh
scripts/productivity-vm/test-productivity-services.sh
```

Destructive restore outline:

1. Deploy `productivity-vm` once to create users, secrets, mounts, and units.
2. Stop the backup timer and productivity services.
3. Mount `/mnt/backups`.
4. Choose a `productivity-vm` appdata snapshot ID.
5. Restore the snapshot to `/` with `restic --verify`.
6. Run `systemd-tmpfiles --create`.
7. Restart PostgreSQL and productivity services.

Garage is standalone S3 in this pass. It does not back Nextcloud primary
storage. `garage.h` is the authenticated S3 API, so anonymous browser requests
to `/` should return AccessDenied. `garage-web.h` is the static website
endpoint; buckets must still be created and enabled for website hosting with
the upstream Garage CLI before serving content.

RustFS is separate S3-compatible storage. It does not share Garage buckets or
credentials. `rustfs.h` is the S3 API and `rustfs-console.h` is the console.
