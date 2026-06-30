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

          testbed-vm runs Fizzy with local SQLite storage, Keeper calendar sync
          with local PostgreSQL and Redis, Listmonk with local PostgreSQL,
          local Mailpit SMTP capture, Authentik integration, and Restic appdata
          backups.

          Persistent state root:
            ${appdata}

          Fizzy state:
            ${cfg.fizzy.stateDir}
            ${cfg.fizzy.stateDir}/storage

          Listmonk state:
            ${cfg.listmonk.stateDir}

          Keeper state:
            ${cfg.keeper.stateDir}
            ${cfg.keeper.stateDir}/redis

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
            Listmonk: ${toString cfg.ports.listmonk} (Gateway nodes only)
            Mailpit UI/API: ${toString cfg.ports.mailpit} (Gateway nodes only)
            Mailpit SMTP: ${toString cfg.ports.mailpitSmtp} (local host firewall closed)

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

          Mail model:
            Fizzy and Listmonk send to local Mailpit on 127.0.0.1:${toString cfg.ports.mailpitSmtp}.
            Mailpit accepts dummy local SMTP AUTH for Fizzy compatibility; no
            real SMTP relay credentials are declared on this host.

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
            7. Restart PostgreSQL, Keeper Redis, Mailpit, Listmonk, Fizzy, Keeper, OIDC provisioning, and the backup timer.

          Services stopped during consistency-first manual backup:
            ${concatStringsSep " " statefulServices}

          Guarded deploy workflow:
            nix develop
            nix flake check
            colmena build --on testbed-vm
            colmena apply --on testbed-vm dry-activate
            scripts/testbed-vm/deploy-testbed.sh
            scripts/testbed-vm/test-testbed-services.sh

          Keep Fizzy secret keys, Keeper auth/encryption/database/OAuth secrets,
          Listmonk admin credentials, OIDC client secrets, SMB credentials, and
          Restic passwords in encrypted secrets only; do not write them into Nix
          files, generated configs, recovery notes, logs, or chat.
    '';
  };
}
