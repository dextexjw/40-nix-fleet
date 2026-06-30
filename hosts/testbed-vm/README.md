# testbed-vm

`testbed-vm` runs Listmonk as a newsletter and mailing-list testbed. Mail is
captured locally by MailHog so campaigns cannot leave the lab until a real SMTP
integration is intentionally added.

## Service URLs

- Listmonk public route: `https://listmonk.jax22.com/`
- Listmonk LAN alias: `http://listmonk.h/`
- Direct backend: `http://10.2.20.129:9000/` from Gateway nodes only
- MailHog UI/API: `http://127.0.0.1:8025/` on `testbed-vm` only

## State

- Appdata root: `/srv/appsdata`
- Listmonk uploads and service state: `/srv/appsdata/listmonk`
- PostgreSQL data: `/srv/appsdata/postgresql`
- PostgreSQL dump: `/srv/appsdata/postgresql-dumps/latest.sql.gz`
- Backup repository: `/mnt/backups/restic/appdata/testbed-vm`

## Secrets

Required SOPS keys:

- `admin-password-hash`
- `beszel-agent-key`
- `beszel-agent-token`
- `checkmate-capture-environment`
- `listmonk-admin-username`
- `listmonk-admin-password`
- `listmonk-oidc-client-secret`
- `restic-password`
- `smb-credentials`

Listmonk uses a SOPS-backed local admin account for break-glass access. Native
OIDC is provisioned through Authentik client `listmonk` for `fleet-admins`.

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

The restore script stops Listmonk, PostgreSQL, MailHog, and the backup timer,
restores `/srv/appsdata`, reapplies declared directories, and restarts service
units.

## Validation

```sh
scripts/testbed-vm/test-testbed-services.sh
```

The helper checks Listmonk, PostgreSQL, MailHog, OIDC provisioning, local HTTP,
Gateway-routed URLs, backup and restore validation, and recent Restic snapshots.
