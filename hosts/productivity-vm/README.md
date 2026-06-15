# productivity-vm

`productivity-vm` runs the personal productivity stack, AFFiNE, the
On-Demand Apps Dashboard, nginx-backed internal apps, Git forges,
OpenSpeedTest, iperf3,
RustDesk, InvoicePlane, Shlink short links, Memos notes, netboot.xyz,
standalone Garage and RustFS object storage, PostgreSQL, MariaDB, appdata
backups, and restore checks.

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
- VM RAM: `4 GB`
- VM CPU cores: `4`
- Swap safety valve: declarative `zramSwap` at `50%` memory
- Backup SMB share: `//nas.home.arpa/backups` mounted at `/mnt/backups`

Application state lives under `/srv/appsdata`, which is the restore-critical
path backed up by Restic.

## Service Access

| Service | Canonical route | Alias | Backend |
| --- | --- | --- | --- |
| AFFiNE | `https://affine.jax22.com` | `http://affine.h` | `10.2.20.114:3010` |
| On-Demand Apps Dashboard | `https://ondemand.jax22.com` | none | `10.2.20.114:8092` from `gateway-vm` only |
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
| Memos | `https://memos.jax22.com` | `http://memos.h` | `10.2.20.114:5230` |
| netboot.xyz WebUI | `https://netbootxyz.jax22.com` | `http://netbootxyz.h` | `10.2.20.114:3001` |
| iperf3 | `iperf3.jax22.com:5201` | `iperf3.h:5201` | `10.2.20.114:5201/tcp+udp` |
| RustDesk | `rustdesk.jax22.com` | `rustdesk.h` | `10.2.20.114:21115-21119/tcp, 21116/udp` |
| Shlink short links/API | `https://s.jax22.com` | `http://s.h` | `10.2.20.114:8088` |
| Shlink Web Client | `https://shlink.jax22.com` | `http://shlink.h` | `10.2.20.114:8089` |
| Garage S3 API | `https://garage.jax22.com` | `http://garage.h` | `10.2.20.114:3900` |
| Garage static web | `https://s3.garage.jax22.com` | `http://s3.garage.h` | `10.2.20.114:3902` |
| RustFS S3 API | `https://s3.rustfs.jax22.com` | `http://s3.rustfs.h` | `10.2.20.114:9000` |
| RustFS console | `https://rustfs.jax22.com` | `http://rustfs.h` | `10.2.20.114:9001` |
| ntfy | `https://ntfy.jax22.com` | `http://ntfy.h` | `10.2.20.114:2586` |

Traefik routes and Homepage cards are declared on `gateway-vm`.
The On-Demand Apps Dashboard route is protected by Authentik forward-auth for
`productivity-users`; its backend port is source-restricted to `gateway-vm`.
netboot.xyz local assets are served at `10.2.20.114:8083`; TFTP is served at
`10.2.20.114:69/udp` with boot file `netboot.xyz.efi`.

## State Paths

Important appdata paths:

- `/srv/appsdata/affine`
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
- `/srv/appsdata/memos`
- `/srv/appsdata/memos-backups`
- `/srv/appsdata/netbootxyz`
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
`productivity-memos-sqlite-backup.service` writes
`/srv/appsdata/memos-backups/latest.db` before Restic backups when the Memos
SQLite database exists.

netboot.xyz runs as `podman-netbootxyz.service` with persistent config and
downloaded assets under `/srv/appsdata/netbootxyz`. Configure the LAN DHCP
server to point option 66 at `10.2.20.114` and option 67 at
`netboot.xyz.efi`. Gateway Traefik routes only the browser UI; the asset server
and TFTP listener are direct Productivity LAN services.

## On-Demand Apps

Homepage cards for AFFiNE, Gitea, Stirling PDF, and Firefly III open the
On-Demand Apps Dashboard instead of assuming the app is already running. The
dashboard starts the allowlisted units, waits for the app health check, redirects
to the normal app URL, and can stop the app again.

Initial bundles:

- `affine`: `redis-affine.service`, then `podman-affine.service`.
- `gitea`: `gitea.service`, then `gitea-oidc-config.service`.
- `stirling-pdf`: `stirling-pdf.service`.
- `firefly`: `phpfpm-firefly-iii.service` and `firefly-iii-cron.timer`.

These units remain installed but are not wanted by boot targets. Core services
such as nginx, PostgreSQL, MariaDB, backups, restore checks, Gateway,
Homepage, Traefik, and Authentik stay always-on. Dashboard actions are refused
while backup, restore-check, dump, app migration, or deployment lock signals are
active under `/run/on-demand-apps-dashboard/maintenance.lock`.

## Secrets

Required shared secrets:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`

Required productivity secrets:

- `affine-environment`
- `authentik-bootstrap-email`
- `firefly-app-key`
- `forgejo-oidc-client-secret`
- `gitea-oidc-client-secret`
- `freshrss-admin-password`
- `freshrss-admin-username`
- `garage-admin-token`
- `garage-metrics-token`
- `garage-rpc-secret`
- `invoiceplane-db-password`
- `memos-admin-pat`
- `memos-oidc-client-secret`
- `nextcloud-admin-password`
- `nextcloud-admin-username`
- `nextcloud-oidc-client-secret`
- `paperless-admin-password`
- `paperless-admin-username`
- `paperless-oidc-client-secret`
- `rustfs-environment`
- `rustfs-oidc-client-secret`
- `searxng-environment`
- `shlink-environment`
- `syncthing-gui-password`
- `syncthing-gui-username`
- `vaultwarden-environment`

Required Gateway/Auth secret for AFFiNE exposure:

- `affine-oidc-client-secret`

Gitea uses native OIDC with Authentik. Authentik provisions the `gitea`
client and allows `productivity-users`; `gitea-oidc-config.service` provisions
the Gitea `authentik` OpenID Connect authentication source using the
SOPS-managed `gitea-oidc-client-secret`. The only allowed callback is
`https://gitea.jax22.com/user/oauth2/authentik/callback`. Local Gitea accounts
and password login remain enabled for break-glass access.

Forgejo uses native OIDC with Authentik. Authentik provisions the `forgejo`
client and allows `productivity-users`; `forgejo-oidc-config.service`
provisions the Forgejo `authentik` OpenID Connect authentication source using
the SOPS-managed `forgejo-oidc-client-secret`. The only allowed callback is
`https://forgejo.jax22.com/user/oauth2/authentik/callback`. Local Forgejo
accounts and password login remain enabled for break-glass access.

Memos uses native OAuth2 with Authentik. Authentik provisions the `memos`
client and allows `productivity-users`; `memos-oidc-config.service` provisions
the Memos identity provider through the Memos API using the SOPS-managed
`memos-admin-pat`. The only allowed callback is
`https://memos.jax22.com/auth/callback`; `http://memos.h` remains a non-SSO LAN
alias. Local password auth and signup policy stay managed in Memos.

Paperless uses native OIDC through django-allauth. Authentik provisions the
`paperless` client and allows `productivity-users`; this host injects
`PAPERLESS_SOCIALACCOUNT_PROVIDERS` from the encrypted
`paperless-oidc-client-secret` through a runtime-only SOPS template owned by
`paperless`. The only allowed callback is
`https://paperless.jax22.com/accounts/oidc/authentik/login/callback/`.
Authentik-backed Paperless accounts are created on first successful OIDC login.
`paperless-oidc-superuser.service` promotes the SOPS-backed admin identity from
`paperless-admin-username` or `authentik-bootstrap-email` to Django staff and
superuser. `paperless-oidc-superuser.timer` retries this after boot so the
admin OIDC account is promoted after its first browser login.
Local Paperless username/password login remains enabled for break-glass access.

Nextcloud uses the native `user_oidc` app. Authentik provisions the `nextcloud`
client and allows `productivity-users`; `nextcloud-oidc-config.service`
installs the Authentik provider with `nextcloud-occ` from the encrypted
`nextcloud-oidc-client-secret`. The only allowed callback is
`https://nextcloud.jax22.com/apps/user_oidc/code`. OIDC-managed users are kept
separate from same-named local users by Nextcloud's unique OIDC user IDs, and
`allow_multiple_user_backends=1` keeps local username/password login available
for break-glass access.

AFFiNE starts on demand as `podman-affine.service` on `10.2.20.114:3010`, stores
uploads and config under `/srv/appsdata/affine`, uses PostgreSQL database
`affine`, and uses `redis-affine.service` as a host-local volatile Redis cache.
The `affine-environment` secret supplies `DB_PASSWORD`; the service generates
the derived `DATABASE_URL` under `/run/affine/environment` at runtime.

Gateway Authentik provisioning creates the `affine` OIDC client for
`productivity-users` with callback `https://affine.jax22.com/oauth/callback`.
AFFiNE's app-side OIDC settings are completed from the AFFiNE admin panel:
`Admin Panel > Settings > OAuth`, OIDC config
`{"args":{},"issuer":"https://auth.jax22.com/application/o/affine","clientId":"affine","clientSecret":"<affine-oidc-client-secret>"}`.
Local AFFiNE email/password login remains available for break-glass access.

FreshRSS is not wired to native OIDC in this NixOS deployment yet. The upstream
FreshRSS OIDC path is Apache `mod_auth_openidc` or the official Apache-based
image; this host currently uses the NixOS FreshRSS module with nginx/PHP-FPM and
form auth, so enabling FreshRSS SSO needs a serving-model change first.

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

- Timer service: `productivity-consistency-backup.service`
- Restic service: `productivity-appdata-backup.service`
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

The manual backup helper records whether each on-demand app was running before
the backup and only restarts those apps afterward.
The scheduled timer uses the same maintenance lock and on-demand quiesce model
before it runs the database dumps and Restic backup.

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
7. Restart PostgreSQL, MariaDB, and always-on productivity services. On-demand
   apps remain stopped until opened through the On-Demand Apps Dashboard.

Garage is standalone S3 in this pass. It does not back Nextcloud primary
storage. `garage.jax22.com` is the authenticated S3 API, so anonymous browser
requests to `/` should return AccessDenied. `s3.garage.jax22.com` is the
static website endpoint; buckets must still be created and enabled for website
hosting with the upstream Garage CLI before serving content. Bucket
virtual-host style is canonical on `jax22.com`; `.h` is only retained as a
named endpoint alias.

RustFS is separate S3-compatible storage. It does not share Garage buckets or
credentials. `s3.rustfs.jax22.com` is the S3 API and `rustfs.jax22.com` is
the console. RustFS virtual-host style is canonical on `jax22.com`; `.h` is only
retained as a named endpoint alias. The console uses Authentik native OIDC for
`fleet-admins` only. Authentik owns the `rustfs-console` client and only allows
`https://rustfs.jax22.com/rustfs/admin/v3/oidc/callback/authentik` as
the callback. `rustfs-oidc-policy.service` ensures the
`rustfs-console-admin` RustFS IAM policy exists for OIDC console sessions; the
S3 API remains access-key based through `rustfs-environment`. Authentik native
OIDC provisioning attaches the self-signed signing key so RustFS can validate
JWKS during startup discovery.

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

Memos stores its SQLite database and local app state under `/srv/appsdata/memos`.
The pre-backup SQLite copy is `/srv/appsdata/memos-backups/latest.db`.
`memos-oidc-config.service` declaratively keeps the Authentik OAuth2 provider
visible on the Memos sign-in page without disabling existing local auth.

Gitea uses Authentik native OIDC for `productivity-users`.
`gitea-oidc-client-secret` is shared between Gateway Authentik provisioning and
`gitea-oidc-config.service`. Local Gitea password login stays enabled for
break-glass access. Gitea is started on demand through the On-Demand Apps Dashboard.

Forgejo uses Authentik native OIDC for `productivity-users`.
`forgejo-oidc-client-secret` is shared between Gateway Authentik provisioning
and `forgejo-oidc-config.service`. Local Forgejo password login stays enabled
for break-glass access.

Paperless uses Authentik native OIDC for `productivity-users`.
`paperless-oidc-client-secret` is shared between Gateway Authentik provisioning
and the Paperless runtime environment template. `paperless-oidc-superuser`
promotes the SOPS-backed admin identity from `paperless-admin-username` or
`authentik-bootstrap-email` to Paperless staff and superuser. Local Paperless
password login stays enabled for break-glass access.

Nextcloud uses Authentik native OIDC for `productivity-users`.
`nextcloud-oidc-client-secret` is shared between Gateway Authentik provisioning
and `nextcloud-oidc-config.service`. The integration is additive: local
Nextcloud accounts, including the admin account from
`nextcloud-admin-username` and `nextcloud-admin-password`, remain valid for
break-glass access.

`rustfs-oidc-policy.service` declaratively keeps the RustFS
`rustfs-console-admin` IAM policy available for Authentik-backed console
sessions. Re-run it after restoring RustFS appdata or rotating
`rustfs-environment` / `rustfs-oidc-client-secret`.
