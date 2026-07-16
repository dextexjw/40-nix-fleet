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
  withoutMetube = (evalTestbed { fleet.testbed.stack.metube.enable = false; }).config;
  unsafeRestoreTarget = builtins.tryEval (
    (evalTestbed { fleet.testbed.stack.backup.restoreCheckTarget = "/srv/restore-check"; })
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
assert !(withoutMetube.fleet.testbed.recovery.applications ? metube);
assert applications.metube.durablePaths == [ "/srv/appsdata/metube" ];
assert
  applications.metube.excludedPaths == [
    "/mnt/media/downloads/metube"
    "/var/lib/metube-downloads"
  ];
assert applications.metube.quiesceUnits == [ "podman-metube.service" ];
assert !unsafeRestoreTarget.success;
assert !invalidDurablePath.success;
assert !duplicateUnitOwnership.success;
assert !missingEnabledApplication.success;
assert !incompleteDeclaration.success;
assert !incompleteDump.success;
pkgs.runCommand "testbed-recovery-lifecycle-evaluation" { } ''
  touch "$out"
''
