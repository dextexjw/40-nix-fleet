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

          testbed-vm runs Listmonk with local PostgreSQL, local MailHog SMTP
          capture, Authentik native OIDC, and Restic appdata backups.

          Persistent state root:
            ${appdata}

          Listmonk state:
            ${cfg.listmonk.stateDir}

          Backup repository:
            ${cfg.backup.repository}

          Password file:
            ${resticPasswordFile}

          Internal routes through Gateway nodes:
      ${serviceRouteLines}

          Direct LAN ports:
            Listmonk: ${toString cfg.ports.listmonk} (Gateway nodes only)
            MailHog UI/API: ${toString cfg.ports.mailhog} (local host firewall closed)
            MailHog SMTP: ${toString cfg.ports.mailhogSmtp} (local host firewall closed)

          Auth model:
            Listmonk exposes public subscription, campaign, media, webhook, and
            tracking endpoints through Gateway. Admin access uses Listmonk native
            OIDC with Authentik client listmonk for fleet-admins and redirect URI
            https://listmonk.jax22.com/auth/oidc. A SOPS-backed local Listmonk
            admin remains available for break-glass access.

          Mail model:
            Listmonk sends to local MailHog on 127.0.0.1:${toString cfg.ports.mailhogSmtp}.
            No real SMTP credentials are declared on this host.

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
            7. Restart PostgreSQL, Listmonk, MailHog, OIDC provisioning, and the backup timer.

          Services stopped during consistency-first manual backup:
            ${concatStringsSep " " statefulServices}

          Guarded deploy workflow:
            nix develop
            nix flake check
            colmena build --on testbed-vm
            colmena apply --on testbed-vm dry-activate
            scripts/testbed-vm/deploy-testbed.sh
            scripts/testbed-vm/test-testbed-services.sh

          Keep Listmonk admin credentials, OIDC client secrets, SMB credentials,
          and Restic passwords in encrypted secrets only; do not write them into
          Nix files, generated configs, recovery notes, logs, or chat.
    '';
  };
}
