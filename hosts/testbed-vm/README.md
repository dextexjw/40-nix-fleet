# testbed-vm

`testbed-vm` runs AFFiNE, Gitea, Stirling PDF, Firefly III, Fizzy as a project-board testbed, Homebox as a home-inventory
testbed, InvoicePlane as an invoicing testbed, Kaneo as a project-management testbed, Keeper as a calendar-sync
testbed, Listmonk as a newsletter and mailing-list testbed, Outline as a
knowledge-base testbed, Plane as a project-management testbed, Postiz as a
social media scheduling testbed, Sure as a personal-finance testbed, and
MeTube as a video-downloader testbed. Mail is captured locally by Mailpit so
test messages cannot leave the lab until a real SMTP integration is
intentionally added.

## Service URLs

- AFFiNE public route: `https://affine.jax22.com/`
- AFFiNE LAN alias: `http://affine.h/`
- AFFiNE direct backend: `http://10.2.20.129:3010/` from Gateway nodes only
- Gitea public route: `https://gitea.jax22.com/`
- Gitea LAN alias: `http://gitea.h/`
- Gitea direct backend: `http://10.2.20.129:9070/` from Gateway nodes only
- Stirling PDF public route: `https://stirling-pdf.jax22.com/`
- Stirling PDF LAN alias: `http://stirling-pdf.h/`
- Stirling PDF direct backend: `http://10.2.20.129:8086/` from Gateway nodes only
- Firefly III public route: `https://firefly.jax22.com/`
- Firefly III LAN alias: `http://firefly.h/`
- Firefly III direct backend: `http://10.2.20.129:80/` from Gateway nodes only
- Fizzy public route: `https://fizzy.jax22.com/`
- Fizzy LAN alias: `http://fizzy.h/`
- Fizzy direct backend: `http://10.2.20.129:9010/` from Gateway nodes only
- Keeper public route: `https://keeper.jax22.com/`
- Keeper direct backend: `http://10.2.20.129:3000/` from Gateway nodes only
- Keeper API health: `http://127.0.0.1:3001/api/health` on `testbed-vm` only
- Homebox public route: `https://homebox.jax22.com/`
- Homebox LAN alias: `http://homebox.h/`
- Homebox direct backend: `http://10.2.20.129:7745/` from Gateway nodes only
- InvoicePlane public route: `https://invoiceplane.jax22.com/`
- InvoicePlane LAN alias: `http://invoiceplane.h/`
- InvoicePlane direct backend: `http://10.2.20.129:9060/` from Gateway nodes only
- InvoicePlane login: `https://invoiceplane.jax22.com/sessions/login`
- Kaneo public route: `https://kaneo.jax22.com/`
- Kaneo LAN alias: `http://kaneo.h/`
- Kaneo direct backend: `http://10.2.20.129:5173/` from Gateway nodes only
- Kaneo health: `http://10.2.20.129:5173/api/health` from Gateway nodes only
- Listmonk public route: `https://listmonk.jax22.com/`
- Listmonk LAN alias: `http://listmonk.h/`
- Listmonk direct backend: `http://10.2.20.129:9000/` from Gateway nodes only
- Outline public route: `https://outline.jax22.com/`
- Outline LAN alias: `http://outline.h/`
- Outline direct backend: `http://10.2.20.129:9050/` from Gateway nodes only
- Outline health: `http://10.2.20.129:9050/_health` from Gateway nodes only
- Plane public route: `https://plane.jax22.com/`
- Plane direct backend: `http://10.2.20.129:9020/` from Gateway nodes only
- Postiz public route: `https://postiz.jax22.com/`
- Postiz LAN alias: `http://postiz.h/`
- Postiz direct backend: `http://10.2.20.129:9040/` from Gateway nodes only
- Sure public route: `https://sure.jax22.com/`
- Sure LAN alias: `http://sure.h/`
- Sure direct backend: `http://10.2.20.129:9030/` from Gateway nodes only
- MeTube public route: `https://metube.jax22.com/`
- MeTube direct backend: `http://10.2.20.129:8081/` from Gateway nodes only
- Mailpit public route: `https://mailpit.jax22.com/`
- Mailpit direct backend: `http://10.2.20.129:8025/` from Gateway nodes only
- Mailpit local SMTP capture: `127.0.0.1:1025` on `testbed-vm`
- Mailpit homelab SMTP capture: `smtp.mailpit.jax22.com:25` through Gateway

## State

- Appdata root: `/srv/appsdata`
- Media SMB share: `//nas.home.arpa/media` mounted at `/mnt/media`
- AFFiNE uploads and config: `/srv/appsdata/affine`
- AFFiNE PostgreSQL database: `affine`
- AFFiNE Redis cache: `redis-affine.service`
- Gitea repositories, LFS, custom config, and dumps: `/srv/appsdata/gitea`
- Gitea PostgreSQL database: `gitea`
- Stirling PDF runtime state: `/srv/appsdata/stirling-pdf`
- Firefly III runtime state: `/srv/appsdata/firefly-iii`
- Fizzy SQLite, queue/cache databases, and uploads: `/srv/appsdata/fizzy/storage`
- Homebox SQLite database, uploads, and generated assets: `/srv/appsdata/homebox`
- InvoicePlane runtime state: `/srv/appsdata/invoiceplane`
- InvoicePlane MariaDB data: `/srv/appsdata/mariadb`
- InvoicePlane MariaDB database: `invoiceplane`
- Kaneo runtime scratch directory: `/srv/appsdata/kaneo`
- Kaneo durable state: PostgreSQL database `kaneo` plus Garage bucket `kaneo-uploads`
- Keeper Redis state and local service data: `/srv/appsdata/keeper`
- Listmonk uploads and service state: `/srv/appsdata/listmonk`
- Outline runtime state: `/srv/appsdata/outline`
- Outline Redis state: `/srv/appsdata/outline/redis`
- Outline PostgreSQL database: `outline`
- Outline object storage: Garage bucket `outline-uploads` on `productivity-vm`
- Plane logs, RabbitMQ, and Redis: `/srv/appsdata/plane`
- Plane PostgreSQL database: `plane`
- Plane object storage: Garage bucket `plane-uploads` on `productivity-vm`
- Postiz uploads, config, PostgreSQL, Redis, and Temporal state:
  `/srv/appsdata/postiz`
- Sure uploads and service state: `/srv/appsdata/sure`
- Sure Redis state: `/srv/appsdata/sure/redis`
- Sure PostgreSQL database: `sure`
- MeTube queue and subscription state: `/srv/appsdata/metube/state`
- MeTube completed downloads: `/mnt/media/downloads/metube` on the NAS media
  share, outside Restic appdata backups
- MeTube temporary downloads: `/var/lib/metube-downloads` on local VM storage,
  outside Restic appdata backups
- PostgreSQL data: `/srv/appsdata/postgresql`
- PostgreSQL dump: `/srv/appsdata/postgresql-dumps/latest.sql.gz`
- MariaDB dump: `/srv/appsdata/mariadb-dumps/latest.sql.gz`
- Backup repository: `/mnt/backups/restic/appdata/testbed-vm`

## Secrets

Required SOPS keys:

- `admin-password-hash`
- `affine-environment`
- `beszel-agent-key`
- `beszel-agent-token`
- `checkmate-capture-environment`
- `firefly-app-key`
- `fizzy-secret-key-base`
- `gitea-oidc-client-secret`
- `homebox-api-key-pepper`
- `homebox-oidc-client-secret`
- `invoiceplane-admin-email`
- `invoiceplane-admin-password`
- `invoiceplane-db-password`
- `invoiceplane-encryption-key`
- `kaneo-auth-secret`
- `kaneo-garage-access-key-id`
- `kaneo-garage-secret-access-key`
- `kaneo-oidc-client-secret`
- `kaneo-postgres-password`
- `keeper-better-auth-secret`
- `keeper-encryption-key`
- `keeper-google-client-id`
- `keeper-google-client-secret`
- `keeper-microsoft-client-id`
- `keeper-microsoft-client-secret`
- `keeper-postgres-password`
- `listmonk-admin-username`
- `listmonk-admin-password`
- `listmonk-oidc-client-secret`
- `outline-garage-access-key-id`
- `outline-garage-secret-access-key`
- `outline-oidc-client-secret`
- `outline-postgres-password`
- `outline-secret-key`
- `outline-utils-secret`
- `plane-admin-email`
- `plane-admin-password`
- `plane-garage-access-key-id`
- `plane-garage-secret-access-key`
- `plane-live-server-secret-key`
- `plane-postgres-password`
- `plane-rabbitmq-password`
- `plane-secret-key`
- `postiz-jwt-secret`
- `postiz-oidc-client-secret`
- `postiz-postgres-password`
- `postiz-temporal-postgres-password`
- `sure-oidc-client-secret`
- `sure-postgres-password`
- `sure-secret-key-base`
- `restic-password`
- `smb-credentials`

Fizzy uses a SOPS-backed `SECRET_KEY_BASE` and sends sign-in mail to local
Mailpit. Mailpit accepts dummy local SMTP AUTH because Fizzy's upstream mailer
requires an auth mode when SMTP is configured; these are not real relay
credentials. The public `fizzy.jax22.com` route is protected by Authentik
forward-auth for `fleet-admins`; the `fizzy.h` LAN alias is unprotected.

To view captured Fizzy sign-in emails from a browser, open
`https://mailpit.jax22.com/`. The route is protected by Authentik forward-auth
for `fleet-admins` and is also linked from Homepage.

Testbed apps submit mail to local Mailpit on `127.0.0.1:1025`. Homelab clients
can submit capture-only mail through Gateway at `smtp.mailpit.jax22.com:25`.
Mailpit accepts dummy SMTP AUTH for compatibility only; there are no real relay
credentials or SOPS secrets for this endpoint.

AFFiNE is exposed at `https://affine.jax22.com/` and `http://affine.h/` as an
always-on container backed by native PostgreSQL database `affine` and
`redis-affine.service`. The `affine-environment` secret supplies `DB_PASSWORD`;
the derived `DATABASE_URL` is generated under `/run/affine/environment` at
runtime. Authentik owns the `affine` client for `productivity-users` with
callback `https://affine.jax22.com/oauth/callback`. Complete AFFiNE's app-side
OIDC setup from the admin panel with issuer
`https://auth.jax22.com/application/o/affine`, client ID `affine`, and the
encrypted `affine-oidc-client-secret`.

Gitea is exposed at `https://gitea.jax22.com/` and `http://gitea.h/` on backend
port `9070` to avoid Keeper's `3000` port on testbed. It uses native PostgreSQL
database `gitea` and native OIDC through Authentik client `gitea` for
`productivity-users` with callback
`https://gitea.jax22.com/user/oauth2/authentik/callback`.
`gitea-oidc-config.service` provisions the `authentik` login source from the
SOPS-managed `gitea-oidc-client-secret`. Local Gitea password login remains
enabled for break-glass access.

Stirling PDF is exposed at `https://stirling-pdf.jax22.com/` and
`http://stirling-pdf.h/` as an always-on service with state under
`/srv/appsdata/stirling-pdf`.

Firefly III is exposed at `https://firefly.jax22.com/` and `http://firefly.h/`
through the testbed nginx/PHP-FPM stack. It uses SQLite-backed appdata under
`/srv/appsdata/firefly-iii` and the SOPS-managed `firefly-app-key`.

The former On-Demand Apps Dashboard is dormant: its source remains in the repo
for reference, but no route, Homepage card, or enabled service imports it.

Listmonk uses a SOPS-backed local admin account for break-glass access. Native
OIDC is provisioned through Authentik client `listmonk` for `fleet-admins`.

InvoicePlane is exposed at `https://invoiceplane.jax22.com/` and
`http://invoiceplane.h/`. Public HTTPS uses Gateway Authentik forward-auth for
`fleet-admins`; InvoicePlane itself remains local-login based with
SOPS-backed initial admin credentials. `invoiceplane-bootstrap.service` drives
the upstream installer only on an empty MariaDB database, verifies the schema
and admin user, then locks setup with `SETUP_COMPLETED=true` and
`DISABLE_SETUP=true` in `/srv/appsdata/invoiceplane/www/ipconfig.php`. The
canonical URL is `https://invoiceplane.jax22.com/` to avoid HTTP redirects.

Outline is exposed at `https://outline.jax22.com/` and `http://outline.h/`
with native OIDC through Authentik client `outline` for `fleet-admins` and
callback `https://outline.jax22.com/auth/oidc.callback`. It uses SOPS-backed
application secrets, a SOPS-backed PostgreSQL role password, native
PostgreSQL, native Redis, local Mailpit SMTP, and Garage bucket
`outline-uploads` on `https://garage.jax22.com` for uploads and attachments.
Deploy `productivity-vm` first when changing the bucket, key, or CORS policy.

Plane Community Edition is exposed at `https://plane.jax22.com/` through
Gateway Authentik forward-auth for `fleet-admins`. Plane itself uses a
SOPS-backed initial instance admin, native PostgreSQL, native Redis, local
RabbitMQ, and Garage bucket `plane-uploads` on `https://garage.jax22.com` for
images, attachments, and other object storage. Deploy `productivity-vm` first
when changing the bucket, key, or CORS policy. No unauthenticated `plane.h` LAN
alias is declared.

Postiz is exposed at `https://postiz.jax22.com/` and `http://postiz.h/` with
native OIDC through Authentik client `postiz` for `fleet-admins` and callback
`https://postiz.jax22.com/settings`. It uses a SOPS-backed JWT secret,
SOPS-backed OIDC client secret, private Postgres and Redis containers, and the
upstream-required Temporal stack under `/srv/appsdata/postiz/temporal`. Local
file uploads are stored in `/srv/appsdata/postiz/uploads` and are covered by
the testbed appdata backup. Social-platform provider credentials are
intentionally blank in the first deployment; add encrypted provider API keys
only when a specific channel integration is intentionally enabled.

Sure is exposed at `https://sure.jax22.com/` and `http://sure.h/` with native
OIDC through Authentik client `sure` for `fleet-admins` and callback
`https://sure.jax22.com/auth/openid_connect/callback`. It uses a SOPS-backed
`SECRET_KEY_BASE`, SOPS-backed PostgreSQL role password, native PostgreSQL,
native Redis, local uploads in `/srv/appsdata/sure/storage`, and local Mailpit
SMTP. Self-service local registration is closed; create the first interactive
account through Authentik OIDC. Local login remains enabled for future
break-glass accounts, but no plaintext local credentials are declared in Nix.
Optional paid AI and market-data integrations are intentionally disabled in the
initial deployment.

MeTube is exposed at `https://metube.jax22.com/` through Authentik forward-auth
for `fleet-admins`. No unauthenticated `metube.h` LAN alias is declared.
Completed files are written to the NAS media mount at
`/mnt/media/downloads/metube`; queue, pending, completed-list, and subscription
state is kept under `/srv/appsdata/metube/state` and is included in the normal
testbed appdata backup. Temporary and in-progress files use local VM storage at
`/var/lib/metube-downloads`.

Keeper uses SOPS-backed auth, encryption, PostgreSQL, and Google/Microsoft
OAuth client secrets. The Google OAuth app must allow
`https://keeper.jax22.com/api/sources/callback/google` and
`https://keeper.jax22.com/api/destinations/callback/google`. The Microsoft app
must allow `https://keeper.jax22.com/api/sources/callback/outlook` and
`https://keeper.jax22.com/api/destinations/callback/outlook`. Keeper requests
Google Calendar events, calendar-list, and email scopes, plus Microsoft
`Calendars.ReadWrite`, `User.Read`, and `offline_access`. Browser access is
protected by Authentik forward-auth at `https://keeper.jax22.com/`. No
`keeper.h` route is declared because Gateway forward-auth only protects TLS
hosts.

Homebox uses native OIDC through Authentik client `homebox` for `fleet-admins`
with callback `https://homebox.jax22.com/api/v1/users/login/oidc/callback`.
Registration is closed by default and local login stays enabled for break-glass
accounts. If the first account cannot be created through OIDC while registration
is closed, temporarily enable `fleet.testbed.stack.homebox.allowRegistration`,
create the initial account, then immediately disable registration and redeploy.

Kaneo uses native OIDC through Authentik client `kaneo` for `fleet-admins` with
callback `https://kaneo.jax22.com/api/auth/oauth2/callback/custom`. Guest access
and password registration are disabled; Authentik-gated OIDC registration remains
open so first sign-in can create the user. Uploads use Garage bucket
`kaneo-uploads` on `https://garage.jax22.com` with path-style S3 URLs. Deploy
`productivity-vm` first when changing the bucket, key, or CORS policy.

After first install or host key rotation:

```sh
nix develop
scripts/testbed-vm/update-testbed-sops-recipient.sh
```

## Deployment

```sh
nix develop
nix flake check
colmena build --on testbed-vm
colmena apply --on testbed-vm dry-activate
scripts/testbed-vm/deploy-testbed.sh
scripts/testbed-vm/test-testbed-services.sh
```

Gateway nodes must be deployed after route or OIDC catalog changes:

```sh
colmena apply --on gateway-vm switch
colmena apply --on gateway2-vm switch
```

## Backup And Restore

Create and verify a fresh backup:

```sh
scripts/testbed-vm/create-testbed-backup.sh
```

Restore requires an explicit snapshot when more than one matching snapshot
exists:

```sh
scripts/testbed-vm/restore-testbed-appdata.sh <snapshot-id>
```

The restore script stops AFFiNE, Gitea, Stirling PDF, Firefly III, Fizzy,
Homebox, InvoicePlane, Kaneo, Keeper, Listmonk, Outline, Plane, Postiz, Sure,
MariaDB, PostgreSQL, Mailpit, Redis, and the backup timer, restores `/srv/appsdata`,
reapplies declared directories and ownership, and restarts service units.
Outline and Plane object data are not in this testbed backup; they live in
Garage buckets `outline-uploads` and `plane-uploads` and are covered by the
`productivity-vm` Garage appdata backup.

## Validation

```sh
scripts/testbed-vm/test-testbed-services.sh
```

The helper checks AFFiNE, Gitea, Stirling PDF, Firefly III, Fizzy, Homebox,
InvoicePlane, Kaneo, Keeper, Listmonk, Outline, Plane, Postiz, Sure, MariaDB,
PostgreSQL, Redis, Mailpit, OIDC and admin provisioning, local HTTP,
Gateway-routed URLs,
homelab SMTP capture, Homepage output, backup and restore validation, and recent
Restic snapshots.
