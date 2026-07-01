# testbed-vm

`testbed-vm` runs Fizzy as a project-board testbed, Homebox as a home-inventory
testbed, Kaneo as a project-management testbed, Keeper as a calendar-sync
testbed, Listmonk as a newsletter and mailing-list testbed, and Plane as a
project-management testbed. Mail is
captured locally by Mailpit so test messages cannot leave the lab until a real
SMTP integration is intentionally added.

## Service URLs

- Fizzy public route: `https://fizzy.jax22.com/`
- Fizzy LAN alias: `http://fizzy.h/`
- Fizzy direct backend: `http://10.2.20.129:9010/` from Gateway nodes only
- Keeper public route: `https://keeper.jax22.com/`
- Keeper direct backend: `http://10.2.20.129:3000/` from Gateway nodes only
- Keeper API health: `http://127.0.0.1:3001/api/health` on `testbed-vm` only
- Homebox public route: `https://homebox.jax22.com/`
- Homebox LAN alias: `http://homebox.h/`
- Homebox direct backend: `http://10.2.20.129:7745/` from Gateway nodes only
- Kaneo public route: `https://kaneo.jax22.com/`
- Kaneo LAN alias: `http://kaneo.h/`
- Kaneo direct backend: `http://10.2.20.129:5173/` from Gateway nodes only
- Kaneo health: `http://10.2.20.129:5173/api/health` from Gateway nodes only
- Listmonk public route: `https://listmonk.jax22.com/`
- Listmonk LAN alias: `http://listmonk.h/`
- Listmonk direct backend: `http://10.2.20.129:9000/` from Gateway nodes only
- Plane public route: `https://plane.jax22.com/`
- Plane direct backend: `http://10.2.20.129:9020/` from Gateway nodes only
- Mailpit public route: `https://mailpit.jax22.com/`
- Mailpit direct backend: `http://10.2.20.129:8025/` from Gateway nodes only
- Mailpit local SMTP capture: `127.0.0.1:1025` on `testbed-vm`
- Mailpit homelab SMTP capture: `smtp.mailpit.jax22.com:25` through Gateway

## State

- Appdata root: `/srv/appsdata`
- Fizzy SQLite, queue/cache databases, and uploads: `/srv/appsdata/fizzy/storage`
- Homebox SQLite database, uploads, and generated assets: `/srv/appsdata/homebox`
- Kaneo runtime scratch directory: `/srv/appsdata/kaneo`
- Kaneo durable state: PostgreSQL database `kaneo` plus Garage bucket `kaneo-uploads`
- Keeper Redis state and local service data: `/srv/appsdata/keeper`
- Listmonk uploads and service state: `/srv/appsdata/listmonk`
- Plane logs, RabbitMQ, and Redis: `/srv/appsdata/plane`
- Plane PostgreSQL database: `plane`
- Plane object storage: Garage bucket `plane-uploads` on `productivity-vm`
- PostgreSQL data: `/srv/appsdata/postgresql`
- PostgreSQL dump: `/srv/appsdata/postgresql-dumps/latest.sql.gz`
- Backup repository: `/mnt/backups/restic/appdata/testbed-vm`

## Secrets

Required SOPS keys:

- `admin-password-hash`
- `beszel-agent-key`
- `beszel-agent-token`
- `checkmate-capture-environment`
- `fizzy-secret-key-base`
- `homebox-api-key-pepper`
- `homebox-oidc-client-secret`
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
- `plane-admin-email`
- `plane-admin-password`
- `plane-garage-access-key-id`
- `plane-garage-secret-access-key`
- `plane-live-server-secret-key`
- `plane-postgres-password`
- `plane-rabbitmq-password`
- `plane-secret-key`
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

Listmonk uses a SOPS-backed local admin account for break-glass access. Native
OIDC is provisioned through Authentik client `listmonk` for `fleet-admins`.

Plane Community Edition is exposed at `https://plane.jax22.com/` through
Gateway Authentik forward-auth for `fleet-admins`. Plane itself uses a
SOPS-backed initial instance admin, native PostgreSQL, native Redis, local
RabbitMQ, and Garage bucket `plane-uploads` on `https://garage.jax22.com` for
images, attachments, and other object storage. Deploy `productivity-vm` first
when changing the bucket, key, or CORS policy. No unauthenticated `plane.h` LAN
alias is declared.

Keeper uses SOPS-backed auth, encryption, and PostgreSQL secrets, plus optional
Google and Microsoft OAuth client fields. Browser access is protected by
Authentik forward-auth at `https://keeper.jax22.com/`. No `keeper.h` route is
declared because Gateway forward-auth only protects TLS hosts.

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

The restore script stops Fizzy, Homebox, Kaneo, Keeper, Listmonk, Plane,
PostgreSQL, Mailpit, Redis, and the backup timer, restores `/srv/appsdata`,
reapplies declared directories and ownership, and restarts service units.
Plane object data is not in this testbed backup; it lives in Garage bucket
`plane-uploads` and is covered by the `productivity-vm` Garage appdata backup.

## Validation

```sh
scripts/testbed-vm/test-testbed-services.sh
```

The helper checks Fizzy, Homebox, Kaneo, Keeper, Listmonk, Plane, PostgreSQL,
Redis, Mailpit, OIDC and admin provisioning, local HTTP, Gateway-routed URLs,
homelab SMTP capture, Homepage output, backup and restore validation, and recent
Restic snapshots.
