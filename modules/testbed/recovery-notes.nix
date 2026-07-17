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
  inherit (testbedLib) cfg resticPasswordFile;
  applications = config.fleet.testbed.recovery.applications;
  renderList = values: optionalString (values != [ ]) (concatStringsSep " " (map toString values));
  renderOwnership =
    rules:
    concatStringsSep "\n" (
      map (rule: "      ${toString rule.path} -> ${rule.user}:${rule.group} ${rule.mode}") rules
    );
  renderDumps =
    dumps:
    if dumps == [ ] then
      "none"
    else
      concatStringsSep " " (map (dump: "${dump.kind}:${toString dump.path}") dumps);
  renderApplication =
    name: declaration:
    let
      excluded = renderList declaration.excludedPaths;
    in
    ''
        ${declaration.displayName} (${name})
          Durable: ${renderList declaration.durablePaths}
          Excluded: ${if excluded == "" then "none" else excluded}
          Database dumps: ${renderDumps declaration.databaseDumps}
          Stop before consistency work: ${renderList declaration.quiesceUnits}
          Restart in order: ${renderList declaration.restartUnits}
          Verify active: ${renderList declaration.verificationUnits}
          Restored ownership:
      ${renderOwnership declaration.ownership}
    '';
  applicationGuidance = concatStringsSep "\n" (mapAttrsToList renderApplication applications);
  dumpPaths = unique (
    concatMap (application: map (dump: dump.path) application.databaseDumps) (attrValues applications)
  );
  verificationUnits = unique (
    concatMap (application: application.verificationUnits) (attrValues applications)
  );
  dumpAssertions = concatMapStringsSep "\n" (path: "test -s '${toString path}'") dumpPaths;
  unitAssertions = concatMapStringsSep "\n" (
    unit: "systemctl is-active --quiet '${unit}'"
  ) verificationUnits;
  verificationUnitArgs = concatMapStringsSep " " escapeShellArg verificationUnits;
  snapshotHostArg = escapeShellArg cfg.backup.snapshotHost;
  snapshotTagArg = escapeShellArg cfg.backup.tag;
in
{
  config = mkIf cfg.enable {
    environment.etc."fleet/testbed-vm.md".text = ''
          testbed-vm recovery lifecycle
          =============================

          This file is generated from fleet.testbed.recovery.applications. Disabled
          applications are absent from this guidance and from host verification.

          Restic identity
          ---------------
          Repository: ${cfg.backup.repository}
          Host: ${cfg.backup.snapshotHost}
          Path: ${cfg.backup.source}
          Tag: ${cfg.backup.tag}
          Password file: ${resticPasswordFile}
          Retention: ${toString cfg.backup.retention.daily} daily, ${toString cfg.backup.retention.weekly} weekly, ${toString cfg.backup.retention.monthly} monthly snapshots

          Snapshot selection
          ------------------
          No matching snapshot: treat the host as a fresh system and do not restore.
          One matching snapshot: the restore command may select it.
          Multiple matching snapshots: require an explicit snapshot ID.
          A requested ID must occur in the matching host/path/tag snapshot list.
          Never guess a snapshot and never restore automatically during deployment
          or upgrade.

          Declared application recovery
          -----------------------------
        ${applicationGuidance}

          Shared database ownership
          -------------------------
      ${renderOwnership config.fleet.testbed.recovery.sharedOwnership}

          Backup and verification
          -----------------------
          mount ${cfg.smb.backupMount}
          systemctl start testbed-appdata-backup.service
          systemctl start testbed-appdata-restore-check.service
          /etc/fleet/testbed-recovery-verify

          Explicit restore
          ----------------
          1. Deploy testbed-vm once to create users, secrets, mounts, and units.
          2. Run: scripts/testbed-vm/restore-testbed-appdata.sh <snapshot-id>
          3. The command stops the backup timer and declared quiesce units.
          4. It verifies the selected snapshot belongs to the Restic identity above.
          5. It moves existing ${cfg.backup.source} aside before restic restore --verify.
          6. It reapplies declared ownership, runs systemd-tmpfiles, and starts units
             in the declared dependency order.
          7. It starts the backup timer and non-destructive restore check.

          Keep database, application, OIDC, SMB, and Restic credentials in encrypted
          secrets only. Never write plaintext secrets into Nix, generated files,
          recovery notes, logs, shell history, or chat.

          Guarded workflow
          ----------------
          nix develop
          nix flake check
          colmena build --on testbed-vm
          colmena apply --on testbed-vm dry-activate
          scripts/testbed-vm/deploy-testbed.sh
          scripts/testbed-vm/test-testbed-services.sh
    '';

    environment.etc."fleet/testbed-recovery-verify" = {
      mode = "0755";
      text = ''
            #!/bin/sh
            set -eu

            systemctl show -P Result 'testbed-appdata-backup.service' | grep -Fxq success
            systemctl show -P Result 'testbed-appdata-restore-check.service' | grep -Fxq success
            systemctl is-active --quiet 'testbed-appdata-backup.timer'
            for unit in ${verificationUnitArgs}; do
              for attempt in $(seq 1 60); do
                if systemctl is-active --quiet "$unit"; then
                  break
                fi
                sleep 1
              done
            done
        ${dumpAssertions}
        ${unitAssertions}
            env \
              RESTIC_REPOSITORY='${cfg.backup.repository}' \
              RESTIC_PASSWORD_FILE='${resticPasswordFile}' \
              restic snapshots \
                --host ${snapshotHostArg} \
                --path '${cfg.backup.source}' \
                --tag ${snapshotTagArg} \
                --latest 3
      '';
    };
  };
}
