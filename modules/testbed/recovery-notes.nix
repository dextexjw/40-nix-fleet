{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  testbedLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib)
    cfg
    appdata
    resticPasswordFile
    serviceRouteLines
    statefulServices
    ;
in
{
  config = mkIf cfg.enable {
    environment.etc."fleet/testbed-vm.md".text = ''
          testbed-vm service model
          ========================

          testbed-vm runs AFFiNE with local PostgreSQL and Redis, Gitea with
          local PostgreSQL and OIDC provisioning, Stirling PDF, Firefly III,
          Fizzy with local SQLite storage, Homebox with local
          SQLite storage, InvoicePlane with local MariaDB and SOPS-backed
          bootstrap secrets, Kaneo with local PostgreSQL and Garage S3 uploads,
          Keeper calendar sync with local PostgreSQL and Redis, Listmonk with
          local PostgreSQL, Outline with local PostgreSQL, Redis, and Garage S3
          uploads, Plane Community Edition with local PostgreSQL,
          Redis, RabbitMQ, and Garage S3 uploads, Postiz with private
          PostgreSQL, Redis, and Temporal containers, Sure with local
          PostgreSQL, Redis, and local uploads, local Mailpit SMTP capture, Authentik
          integration, and Restic appdata backups.

          Persistent state root:
            ${appdata}

          AFFiNE state:
            ${cfg.affine.stateDir}
            ${cfg.affine.stateDir}/storage
            ${cfg.affine.stateDir}/config
            PostgreSQL database: ${cfg.affine.databaseName}

          Gitea state:
            ${appdata}/gitea
            PostgreSQL database: gitea

          Stirling PDF state:
            ${appdata}/stirling-pdf

          Firefly III state:
            ${appdata}/firefly-iii

          Fizzy state:
            ${cfg.fizzy.stateDir}
            ${cfg.fizzy.stateDir}/storage

          Listmonk state:
            ${cfg.listmonk.stateDir}

          Outline state:
            ${cfg.outline.stateDir}
            ${cfg.outline.stateDir}/redis
            PostgreSQL database: ${cfg.outline.databaseName}
            Garage bucket: ${cfg.outline.s3.bucket} (covered by productivity-vm Garage backups)

          Homebox state:
            ${cfg.homebox.stateDir}
            ${cfg.homebox.stateDir}/data

          InvoicePlane state:
            ${cfg.invoiceplane.stateDir}
            ${cfg.invoiceplane.stateDir}/www
            MariaDB database: ${cfg.invoiceplane.databaseName}

          Kaneo state:
            ${cfg.kaneo.stateDir}
            PostgreSQL database: ${cfg.kaneo.databaseName}
            Garage bucket: ${cfg.kaneo.s3.bucket}

          Keeper state:
            ${cfg.keeper.stateDir}
            ${cfg.keeper.stateDir}/redis

          Plane state:
            ${cfg.plane.stateDir}
            ${cfg.plane.stateDir}/rabbitmq
            ${cfg.plane.stateDir}/redis
            PostgreSQL database: plane
            Garage bucket: ${cfg.plane.garageBucket} (covered by productivity-vm Garage backups)

          Postiz state:
            ${cfg.postiz.stateDir}
            ${cfg.postiz.stateDir}/config
            ${cfg.postiz.stateDir}/uploads
            ${cfg.postiz.stateDir}/postgresql
            ${cfg.postiz.stateDir}/redis
            ${cfg.postiz.stateDir}/temporal/elasticsearch
            ${cfg.postiz.stateDir}/temporal/postgresql

          Sure state:
            ${cfg.sure.stateDir}
            ${cfg.sure.stateDir}/redis
            ${cfg.sure.stateDir}/storage
            PostgreSQL database: ${cfg.sure.databaseName}

          Backup repository:
            ${cfg.backup.repository}

          Password file:
            ${resticPasswordFile}

          Internal routes through Gateway nodes:
      ${serviceRouteLines}

          Direct LAN ports:
            AFFiNE: ${toString cfg.ports.affine} (Gateway nodes only)
            Gitea: ${toString cfg.ports.gitea} (Gateway nodes only)
            Stirling PDF: ${toString cfg.ports.stirlingPdf} (Gateway nodes only)
            Firefly III: 80 (Gateway nodes only)
            Fizzy: ${toString cfg.ports.fizzy} (Gateway nodes only)
            InvoicePlane: ${toString cfg.ports.invoiceplane} (Gateway nodes only)
            Keeper Web: ${toString cfg.ports.keeper} (Gateway nodes only)
            Keeper API: ${toString cfg.ports.keeperApi} (local host only)
            Keeper Redis: ${toString cfg.ports.keeperRedis} (local host only)
            Homebox: ${toString cfg.ports.homebox} (Gateway nodes only)
            Kaneo: ${toString cfg.ports.kaneo} (Gateway nodes only)
            Listmonk: ${toString cfg.ports.listmonk} (Gateway nodes only)
            Plane: ${toString cfg.ports.plane} (Gateway nodes only)
            Plane RabbitMQ: ${toString cfg.ports.planeRabbitmq} (local host only)
            Plane Redis: ${toString cfg.ports.planeRedis} (local host only)
            Postiz: ${toString cfg.ports.postiz} (Gateway nodes only)
            Sure: ${toString cfg.ports.sure} (Gateway nodes only)
            Sure Redis: ${toString cfg.ports.sureRedis} (local host only)
            Mailpit UI/API: ${toString cfg.ports.mailpit} (Gateway nodes only)
            Mailpit SMTP backend: ${toString cfg.ports.mailpitSmtp} (Gateway nodes only)
            Mailpit SMTP homelab endpoint: smtp.mailpit.jax22.com:25
            Outline: ${toString cfg.ports.outline} (Gateway nodes only)
            Outline Redis: ${toString cfg.ports.outlineRedis} (local host only)

          Auth model:
            AFFiNE exposes browser access through native OIDC with Authentik
            client affine for productivity-users and redirect URI
            https://affine.jax22.com/oauth/callback. affine-environment
            supplies DB_PASSWORD at runtime and the derived DATABASE_URL is
            generated outside the Nix store.

            Gitea exposes browser access through native OIDC with Authentik
            client gitea for productivity-users and redirect URI
            https://gitea.jax22.com/user/oauth2/authentik/callback.
            gitea-oidc-config.service provisions the app-side login source
            from gitea-oidc-client-secret. Local password login remains enabled
            for break-glass access. The backend listens on
            ${toString cfg.ports.gitea} to avoid Keeper's port 3000.

            Stirling PDF exposes browser access at
            https://stirling-pdf.jax22.com/ and http://stirling-pdf.h/.

            Firefly III exposes browser access at https://firefly.jax22.com/
            and http://firefly.h/ and uses firefly-app-key from SOPS.

            The former On-Demand Apps Dashboard is dormant: source files remain
            in the repository for reference, but no route, Homepage card, or
            enabled unit imports it.

            Fizzy public HTTPS access uses Authentik forward-auth for
            fleet-admins. The fizzy.h LAN alias is unprotected. Fizzy itself
            uses email-link sign-in through local Mailpit.

            InvoicePlane browser access is routed as https://invoiceplane.jax22.com/
            through Authentik forward-auth for fleet-admins. The invoiceplane.h
            LAN alias follows the Gateway catalog behavior. InvoicePlane itself
            uses local login, SOPS-backed initial admin credentials, local
            MariaDB database ${cfg.invoiceplane.databaseName}, and canonical
            URL ${cfg.invoiceplane.externalUrl}/. The bootstrap unit only runs
            the installer on an empty database and then sets setup disabled in
            ${cfg.invoiceplane.stateDir}/www/ipconfig.php.

            Listmonk exposes public subscription, campaign, media, webhook, and
            tracking endpoints through Gateway. Admin access uses Listmonk native
            OIDC with Authentik client listmonk for fleet-admins and redirect URI
            https://listmonk.jax22.com/auth/oidc. A SOPS-backed local Listmonk
            admin remains available for break-glass access.

            Outline exposes browser access through native OIDC with Authentik
            client outline for fleet-admins and redirect URI
            https://outline.jax22.com/auth/oidc.callback. It uses local
            PostgreSQL, local Redis, local Mailpit SMTP, and Garage bucket
            ${cfg.outline.s3.bucket} through ${cfg.outline.s3.endpoint}. Deploy
            productivity-vm first when changing the bucket, key, or CORS policy.

            Mailpit browser access is routed as https://mailpit.jax22.com/
            through Authentik forward-auth for fleet-admins. It contains sign-in
            links, so no unauthenticated LAN alias is declared.

            Keeper browser access is routed as https://keeper.jax22.com/
            through Authentik forward-auth for fleet-admins. No keeper.h LAN
            alias is declared because Gateway forward-auth only protects TLS
            hosts.

            Homebox exposes browser access through native OIDC with Authentik
            client homebox for fleet-admins and redirect URI
            https://homebox.jax22.com/api/v1/users/login/oidc/callback. Public
            registration is disabled by default; local login remains enabled for
            break-glass accounts. If the first account cannot be created through
            OIDC, temporarily enable registration, create the account, then
            disable registration and redeploy.

            Kaneo exposes browser access through native OIDC with Authentik
            client kaneo for fleet-admins and redirect URI
            https://kaneo.jax22.com/api/auth/oauth2/callback/custom. Guest
            access and password registration are disabled; Authentik-gated OIDC
            registration remains enabled for first-user creation. Uploads use
            Garage bucket ${cfg.kaneo.s3.bucket} through ${cfg.kaneo.s3.endpoint}
            with path-style S3 URLs.

            Plane browser access is routed as https://plane.jax22.com/ through
            Authentik forward-auth for fleet-admins. Plane itself uses a
            SOPS-backed initial instance admin, local PostgreSQL, local Redis,
            local RabbitMQ, and Garage bucket ${cfg.plane.garageBucket} through
            ${cfg.plane.garageEndpoint}. No plane.h LAN alias is declared.

            Postiz exposes browser access through native OIDC with Authentik
            client postiz for fleet-admins and redirect URI
            https://postiz.jax22.com/settings. It keeps local uploads in
            ${cfg.postiz.stateDir}/uploads and runs the upstream-required
            Temporal stack privately under ${cfg.postiz.stateDir}/temporal.
            Social-platform provider credentials are intentionally blank until
            each channel integration is explicitly enabled.

            Sure exposes browser access through native OIDC with Authentik
            client sure for fleet-admins and redirect URI
            https://sure.jax22.com/auth/openid_connect/callback. Self-service
            local registration is closed; the first interactive account should
            be created through Authentik OIDC. Local login remains enabled for
            break-glass accounts.

          Mail model:
            Fizzy, Homebox, Kaneo, Listmonk, Outline, and Sure send to local Mailpit on 127.0.0.1:${toString cfg.ports.mailpitSmtp}.
            Homelab clients can submit capture-only mail through Gateway at
            smtp.mailpit.jax22.com:25. Mailpit accepts dummy SMTP AUTH for
            compatibility; no real SMTP relay credentials or SOPS secrets are
            declared for this endpoint.

          Backup validation:
            mount ${cfg.smb.backupMount}
            systemctl start testbed-appdata-backup.service
            systemctl start testbed-appdata-restore-check.service
            systemctl status testbed-appdata-backup.service testbed-appdata-restore-check.service

          Restore outline:
            1. Deploy testbed-vm once to create users, secrets, mounts, and units.
            2. Stop testbed-appdata-backup.timer and stateful services.
            3. Mount ${cfg.smb.backupMount}.
            4. Choose a testbed-vm/appsdata snapshot ID.
            5. Restore the snapshot to / with restic --verify.
            6. Run systemd-tmpfiles --create.
            7. Restart MariaDB, PostgreSQL, Redis, RabbitMQ, AFFiNE, Gitea, Stirling PDF, Firefly III, InvoicePlane, Outline, Plane, Postiz, Sure, Mailpit, Listmonk, Homebox, Kaneo, Fizzy, Keeper, provisioning units, and the backup timer.

          Services stopped during consistency-first manual backup:
            ${concatStringsSep " " statefulServices}

          Guarded deploy workflow:
            nix develop
            nix flake check
            colmena build --on testbed-vm
            colmena apply --on testbed-vm dry-activate
            scripts/testbed-vm/deploy-testbed.sh
            scripts/testbed-vm/test-testbed-services.sh

          Keep AFFiNE database secrets, Gitea OIDC secrets, Firefly app keys,
          Fizzy secret keys, Homebox API/OIDC secrets, InvoicePlane admin,
          database, and encryption secrets, Kaneo auth,
          database, OIDC, and Garage S3 secrets, Keeper auth/encryption/database/OAuth
          secrets, Listmonk admin credentials, Outline application, database,
          OIDC, and Garage S3 secrets, Plane
          application, database, queue, object storage, and admin bootstrap
          secrets, Postiz JWT, database, Temporal database, and OIDC secrets,
          Sure application, database, and OIDC secrets, SMB credentials, and
          Restic passwords in encrypted secrets only; do not write them into Nix
          files, generated configs, recovery notes, logs, or chat.
    '';
  };
}
