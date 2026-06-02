# productivity-vm

`productivity-vm` runs the personal productivity stack, nginx-backed internal
apps, Git forges, OpenSpeedTest, iperf3, RustDesk, InvoicePlane, Shlink short
links, standalone Garage and RustFS object storage, PostgreSQL, MariaDB,
appdata backups, and restore checks.

Fleet inventory lives in `../../hosts.nix`. Host configuration lives in
`configuration.nix` and imports the stack from
`../../modules/productivity/`.

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

| Service | Canonical route | Alias | Backend |
| --- | --- | --- | --- |
| Gitea | `https://gitea.jax22.com` | `http://gitea.h` | `10.2.20.114:3000` |
| Forgejo | `https://forgejo.jax22.com` | `http://forgejo.h` | `10.2.20.114:3002` |
| Material for MkDocs | `https://docs.jax22.com` | `http://docs.h` | `10.2.20.114:80` |
| Paperless-ngx | `https://paperless.jax22.com` | `http://paperless.h` | `10.2.20.114:80` |
| FreshRSS | `https://freshrss.jax22.com` | `http://freshrss.h` | `10.2.20.114:80` |
| SearXNG | `https://searxng.jax22.com` | `http://searxng.h` | `10.2.20.114:8087` |
| PrivateBin | `https://privatebin.jax22.com` | `http://privatebin.h` | `10.2.20.114:80` |
| Vaultwarden | `https://vaultwarden.jax22.com` | `http://vaultwarden.h` | `10.2.20.114:8222` |
| Syncthing | `https://syncthing.jax22.com` | `http://syncthing.h` | `10.2.20.114:8384` |
| Stirling PDF | `https://stirling-pdf.jax22.com` | `http://stirling-pdf.h` | `10.2.20.114:8086` |
| Firefly III | `https://firefly.jax22.com` | `http://firefly.h` | `10.2.20.114:80` |
| Nextcloud | `https://nextcloud.jax22.com` | `http://nextcloud.h` | `10.2.20.114:80` |
| OpenSpeedTest | `https://openspeedtest.jax22.com` | `http://openspeedtest.h` | `10.2.20.114:8989` |
| InvoicePlane | `https://invoiceplane.jax22.com` | `http://invoiceplane.h` | `10.2.20.114:80` |
| iperf3 | `iperf3.jax22.com:5201` | `iperf3.h:5201` | `10.2.20.114:5201/tcp+udp` |
| RustDesk | `rustdesk.jax22.com` | `rustdesk.h` | `10.2.20.114:21115-21119/tcp, 21116/udp` |
| Shlink short links/API | `https://s.jax22.com` | `http://s.h` | `10.2.20.114:8088` |
| Shlink Web Client | `https://shlink.jax22.com` | `http://shlink.h` | `10.2.20.114:8089` |
| Garage S3 API | `https://garage.jax22.com` | `http://garage.h` | `10.2.20.114:3900` |
| Garage static web | `https://garage-web.jax22.com` | `http://garage-web.h` | `10.2.20.114:3902` |
| RustFS S3 API | `https://rustfs.jax22.com` | `http://rustfs.h` | `10.2.20.114:9000` |
| RustFS console | `https://rustfs-console.jax22.com` | `http://rustfs-console.h` | `10.2.20.114:9001` |
| ntfy | `https://ntfy.jax22.com` | `http://ntfy.h` | `10.2.20.114:2586` |

Traefik routes and Homepage cards are declared on `gateway-vm`.

## State Paths

Important appdata paths:

- `/srv/appsdata/gitea`
- `/srv/appsdata/forgejo`
- `/srv/appsdata/mkdocs`
- `/srv/appsdata/paperless`
- `/srv/appsdata/freshrss`
- `/srv/appsdata/privatebin`
- `/srv/appsdata/shlink`
- `/srv/appsdata/firefly-iii`
- `/srv/appsdata/nextcloud`
- `/srv/appsdata/invoiceplane`
- `/srv/appsdata/vaultwarden`
- `/srv/appsdata/syncthing`
- `/srv/appsdata/stirling-pdf`
- `/srv/appsdata/rustdesk`
- `/srv/appsdata/garage`
- `/srv/appsdata/rustfs`
- `/srv/appsdata/ntfy`
- `/srv/appsdata/mariadb`
- `/srv/appsdata/mariadb-dumps`
- `/srv/appsdata/postgresql`
- `/srv/appsdata/postgresql-dumps`

`productivity-postgresql-dump.service` writes
`/srv/appsdata/postgresql-dumps/latest.sql.gz` before Restic backups.
`productivity-mariadb-dump.service` writes
`/srv/appsdata/mariadb-dumps/latest.sql.gz` before Restic backups.

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
- `invoiceplane-db-password`
- `nextcloud-admin-password`
- `paperless-admin-password`
- `rustfs-environment`
- `searxng-environment`
- `shlink-environment`
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
7. Restart PostgreSQL, MariaDB, and productivity services.

Garage is standalone S3 in this pass. It does not back Nextcloud primary
storage. `garage.jax22.com` is the authenticated S3 API, so anonymous browser
requests to `/` should return AccessDenied. `garage-web.jax22.com` is the
static website endpoint; buckets must still be created and enabled for website
hosting with the upstream Garage CLI before serving content. Bucket
virtual-host style is canonical on `jax22.com`; `.h` is only retained as a
named endpoint alias.

RustFS is separate S3-compatible storage. It does not share Garage buckets or
credentials. `rustfs.jax22.com` is the S3 API and `rustfs-console.jax22.com` is
the console. RustFS virtual-host style is canonical on `jax22.com`; `.h` is only
retained as a named endpoint alias.

InvoicePlane uses MariaDB database `invoiceplane` and persistent runtime state
under `/srv/appsdata/invoiceplane`. Complete initial setup at
`http://invoiceplane.jax22.com/index.php/setup`, then lock setup by setting
`DISABLE_SETUP=true` in `/srv/appsdata/invoiceplane/www/ipconfig.php`.

RustDesk clients should use `rustdesk.jax22.com` as the ID server. The server
public key is stored at `/srv/appsdata/rustdesk/id_ed25519.pub`.

iperf3 is available through Gateway and direct productivity-vm access:

```sh
iperf3 -c iperf3.jax22.com -p 5201
iperf3 -u -c iperf3.jax22.com -p 5201
```

Shlink uses `s.jax22.com` for short links and its API. The local Shlink Web
Client is served at `shlink.jax22.com`. Get the API key from the encrypted
`shlink-environment` secret, then add `https://s.jax22.com` in the web client.
Do not preconfigure the web client with the API key because that static
configuration is browser-readable.
