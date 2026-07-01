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

          testbed-vm runs Fizzy with local SQLite storage, Homebox with local
          SQLite storage, Kaneo with local PostgreSQL and Garage S3 uploads,
          Keeper calendar sync with local PostgreSQL and Redis, Listmonk with
          local PostgreSQL, Plane Community Edition with local PostgreSQL,
          Redis, RabbitMQ, and Garage S3 uploads, local Mailpit SMTP capture,
          Authentik integration, and Restic appdata backups.

          Persistent state root:
            ${appdata}

          Fizzy state:
            ${cfg.fizzy.stateDir}
            ${cfg.fizzy.stateDir}/storage

          Listmonk state:
            ${cfg.listmonk.stateDir}

          Homebox state:
            ${cfg.homebox.stateDir}
            ${cfg.homebox.stateDir}/data

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

          Backup repository:
            ${cfg.backup.repository}

          Password file:
            ${resticPasswordFile}

          Internal routes through Gateway nodes:
      ${serviceRouteLines}

          Direct LAN ports:
            Fizzy: ${toString cfg.ports.fizzy} (Gateway nodes only)
            Keeper Web: ${toString cfg.ports.keeper} (Gateway nodes only)
            Keeper API: ${toString cfg.ports.keeperApi} (local host only)
            Keeper Redis: ${toString cfg.ports.keeperRedis} (local host only)
            Homebox: ${toString cfg.ports.homebox} (Gateway nodes only)
            Kaneo: ${toString cfg.ports.kaneo} (Gateway nodes only)
            Listmonk: ${toString cfg.ports.listmonk} (Gateway nodes only)
            Plane: ${toString cfg.ports.plane} (Gateway nodes only)
            Plane RabbitMQ: ${toString cfg.ports.planeRabbitmq} (local host only)
            Plane Redis: ${toString cfg.ports.planeRedis} (local host only)
            Mailpit UI/API: ${toString cfg.ports.mailpit} (Gateway nodes only)
            Mailpit SMTP backend: ${toString cfg.ports.mailpitSmtp} (Gateway nodes only)
            Mailpit SMTP homelab endpoint: smtp.mailpit.jax22.com:25

          Auth model:
            Fizzy public HTTPS access uses Authentik forward-auth for
            fleet-admins. The fizzy.h LAN alias is unprotected. Fizzy itself
            uses email-link sign-in through local Mailpit.

            Listmonk exposes public subscription, campaign, media, webhook, and
            tracking endpoints through Gateway. Admin access uses Listmonk native
            OIDC with Authentik client listmonk for fleet-admins and redirect URI
            https://listmonk.jax22.com/auth/oidc. A SOPS-backed local Listmonk
            admin remains available for break-glass access.

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

          Mail model:
            Fizzy, Homebox, Kaneo, and Listmonk send to local Mailpit on 127.0.0.1:${toString cfg.ports.mailpitSmtp}.
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
            7. Restart PostgreSQL, Redis, RabbitMQ, Plane, Mailpit, Listmonk, Homebox, Kaneo, Fizzy, Keeper, provisioning units, and the backup timer.

          Services stopped during consistency-first manual backup:
            ${concatStringsSep " " statefulServices}

          Guarded deploy workflow:
            nix develop
            nix flake check
            colmena build --on testbed-vm
            colmena apply --on testbed-vm dry-activate
            scripts/testbed-vm/deploy-testbed.sh
            scripts/testbed-vm/test-testbed-services.sh

          Keep Fizzy secret keys, Homebox API/OIDC secrets, Kaneo auth,
          database, OIDC, and Garage S3 secrets, Keeper auth/encryption/database/OAuth
          secrets, Listmonk admin credentials, OIDC client secrets, Plane
          application, database, queue, object storage, and admin bootstrap
          secrets, SMB credentials, and Restic passwords in encrypted secrets only; do not
          write them into Nix files, generated configs, recovery notes, logs, or
          chat.
    '';
  };
}
