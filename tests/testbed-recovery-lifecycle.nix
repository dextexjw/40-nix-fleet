{
  nixpkgs,
  pkgs,
  system,
}:

let
  evalTestbed =
    extraModule:
    nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ../modules/testbed
        {
          fleet.testbed.stack.enable = true;
          fleet.testbed.stack.secrets.enable = false;
        }
        extraModule
      ];
    };

  enabled = (evalTestbed { }).config;
  disabled =
    (evalTestbed (
      { lib, ... }:
      {
        fleet.testbed.stack.enable = lib.mkForce false;
      }
    )).config;
  withoutMetube = (evalTestbed { fleet.testbed.stack.metube.enable = false; }).config;
  withMutatedMetube =
    (evalTestbed (
      { lib, ... }:
      {
        fleet.testbed.recovery.applications.metube = {
          databaseDumps = [ ];
          displayName = "MeTube";
          durablePaths = lib.mkForce [ "/srv/appsdata/metube-shared-proof" ];
          excludedPaths = [
            "/mnt/media/downloads/metube"
            "/var/lib/metube-downloads"
          ];
          ownership = lib.mkForce [
            {
              group = "testbed";
              mode = "0750";
              path = "/srv/appsdata/metube-shared-proof";
              user = "1000";
            }
          ];
          quiesceUnits = [ "podman-metube.service" ];
          restartUnits = [ "podman-metube.service" ];
          verificationUnits = lib.mkForce [ "metube-shared-proof.service" ];
        };
      }
    )).config;
  unsafeRestoreTarget = builtins.tryEval (
    (evalTestbed { fleet.testbed.stack.backup.restoreCheckTarget = "/srv/restore-check"; })
    .config.system.build.toplevel
  );
  traversingRestoreTarget = builtins.tryEval (
    (evalTestbed { fleet.testbed.stack.backup.restoreCheckTarget = "/var/tmp/../srv"; })
    .config.system.build.toplevel
  );
  invalidDurablePath = builtins.tryEval (
    (evalTestbed {
      fleet.testbed.recovery.applications.affine.durablePaths = [ "/var/lib/affine" ];
    }).config.system.build.toplevel
  );
  duplicateUnitOwnership = builtins.tryEval (
    (evalTestbed {
      fleet.testbed.recovery.applications.duplicate = {
        databaseDumps = [ ];
        durablePaths = [ "/srv/appsdata/duplicate" ];
        excludedPaths = [ ];
        ownership = [
          {
            group = "testbed";
            mode = "0750";
            path = "/srv/appsdata/duplicate";
            user = "root";
          }
        ];
        quiesceUnits = [ "podman-metube.service" ];
        restartUnits = [ "podman-metube.service" ];
        verificationUnits = [ "podman-metube.service" ];
      };
    }).config.system.build.toplevel
  );
  missingEnabledApplication = builtins.tryEval (
    (evalTestbed { fleet.testbed.recovery.applications = { }; }).config.system.build.toplevel
  );
  incompleteDeclaration = builtins.tryEval (
    (evalTestbed {
      fleet.testbed.recovery.applications.incomplete = {
        durablePaths = [ "/srv/appsdata/incomplete" ];
      };
    }).config.system.build.toplevel
  );
  incompleteDump = builtins.tryEval (
    (evalTestbed {
      fleet.testbed.recovery.applications.affine.databaseDumps = [
        {
          kind = "postgresql";
          path = "/srv/appsdata/postgresql-dumps/latest.sql.gz";
        }
      ];
    }).config.system.build.toplevel
  );
  applications = enabled.fleet.testbed.recovery.applications;
  guidance = enabled.environment.etc."fleet/testbed-vm.md".text;
  verification = enabled.environment.etc."fleet/testbed-recovery-verify".text;
  guidanceWithoutMetube = withoutMetube.environment.etc."fleet/testbed-vm.md".text;
  verificationWithoutMetube = withoutMetube.environment.etc."fleet/testbed-recovery-verify".text;
  mutatedGuidance = withMutatedMetube.environment.etc."fleet/testbed-vm.md".text;
  mutatedVerification = withMutatedMetube.environment.etc."fleet/testbed-recovery-verify".text;
  mutatedRuntimeContract = withMutatedMetube.environment.etc."fleet/testbed-recovery.sh".text;
  runtimeContract = enabled.environment.etc."fleet/testbed-recovery.sh".text;
  expectedApplications = [
    "affine"
    "firefly"
    "fizzy"
    "gitea"
    "homebox"
    "invoiceplane"
    "kaneo"
    "keeper"
    "listmonk"
    "metube"
    "outline"
    "plane"
    "postiz"
    "stirling-pdf"
    "sure"
  ];
in
assert builtins.attrNames applications == expectedApplications;
assert disabled.fleet.testbed.recovery.applications == { };
assert !(withoutMetube.fleet.testbed.recovery.applications ? metube);
assert !(builtins.elem "gitea-oidc-config.service" applications.gitea.restartUnits);
assert builtins.elem "listmonk-oidc-config.service" applications.listmonk.restartUnits;
assert applications.metube.durablePaths == [ "/srv/appsdata/metube" ];
assert
  applications.metube.excludedPaths == [
    "/mnt/media/downloads/metube"
    "/var/lib/metube-downloads"
  ];
assert applications.metube.quiesceUnits == [ "podman-metube.service" ];
assert nixpkgs.lib.hasInfix "Repository: /mnt/backups/restic/appdata/testbed-vm" guidance;
assert nixpkgs.lib.hasInfix "Host: testbed-vm" guidance;
assert nixpkgs.lib.hasInfix "Path: /srv/appsdata" guidance;
assert nixpkgs.lib.hasInfix "Tag: appsdata" guidance;
assert nixpkgs.lib.hasInfix "Multiple matching snapshots: require an explicit snapshot ID" guidance;
assert nixpkgs.lib.hasInfix "MeTube (metube)" guidance;
assert nixpkgs.lib.hasInfix "Durable: /srv/appsdata/metube" guidance;
assert nixpkgs.lib.hasInfix "Excluded: /mnt/media/downloads/metube /var/lib/metube-downloads"
  guidance;
assert nixpkgs.lib.hasInfix "test -s '/srv/appsdata/postgresql-dumps/latest.sql.gz'" verification;
assert nixpkgs.lib.hasInfix "systemctl is-active --quiet 'testbed-appdata-backup.timer'"
  verification;
assert nixpkgs.lib.hasInfix "systemctl is-active --quiet 'podman-metube.service'" verification;
assert !(nixpkgs.lib.hasInfix "MeTube (metube)" guidanceWithoutMetube);
assert !(nixpkgs.lib.hasInfix "podman-metube.service" verificationWithoutMetube);
assert nixpkgs.lib.hasInfix "/srv/appsdata/metube-shared-proof" mutatedGuidance;
assert nixpkgs.lib.hasInfix "/srv/appsdata/metube-shared-proof" mutatedRuntimeContract;
assert nixpkgs.lib.hasInfix "metube-shared-proof.service" mutatedGuidance;
assert nixpkgs.lib.hasInfix "metube-shared-proof.service" mutatedVerification;
assert nixpkgs.lib.hasInfix "metube-shared-proof.service" mutatedRuntimeContract;
assert nixpkgs.lib.hasInfix "podman-metube.service" runtimeContract;
assert nixpkgs.lib.hasInfix "/srv/appsdata/metube" runtimeContract;
assert
  !(nixpkgs.lib.hasInfix "podman-metube.service"
    withoutMetube.environment.etc."fleet/testbed-recovery.sh".text
  );
assert !unsafeRestoreTarget.success;
assert !traversingRestoreTarget.success;
assert !invalidDurablePath.success;
assert !duplicateUnitOwnership.success;
assert !missingEnabledApplication.success;
assert !incompleteDeclaration.success;
assert !incompleteDump.success;
pkgs.runCommand "testbed-recovery-lifecycle-evaluation" { } ''
  touch "$out"
''
