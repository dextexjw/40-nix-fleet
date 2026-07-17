{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.testbed.stack;
  recoveryCfg = config.fleet.testbed.recovery;

  ownershipType = types.submodule {
    options = {
      path = mkOption {
        type = types.path;
        description = "Durable path whose ownership is normalized after restore.";
      };
      user = mkOption {
        type = types.str;
        description = "User that owns the restored path.";
      };
      group = mkOption {
        type = types.str;
        description = "Group that owns the restored path.";
      };
      mode = mkOption {
        type = types.strMatching "[0-7]{4}";
        example = "0750";
        description = "Four-digit mode applied to the restored path.";
      };
    };
  };

  dumpType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "mariadb"
          "postgresql"
        ];
        description = "Database engine used to create the dump.";
      };
      path = mkOption {
        type = types.path;
        description = "Restore-critical path containing the completed dump.";
      };
      unit = mkOption {
        type = types.strMatching ".+\\.service";
        description = "Oneshot systemd unit that creates the dump.";
      };
    };
  };

  applicationType = types.submodule {
    options = {
      databaseDumps = mkOption {
        type = types.listOf dumpType;
        description = "Database dumps required before snapshotting the application.";
      };
      durablePaths = mkOption {
        type = types.nonEmptyListOf types.path;
        description = "Restore-critical application paths below the Testbed appdata root.";
      };
      excludedPaths = mkOption {
        type = types.listOf types.path;
        description = "Replaceable or temporary application paths intentionally outside the backup.";
      };
      ownership = mkOption {
        type = types.nonEmptyListOf ownershipType;
        description = "Ownership rules applied after restoring durable paths.";
      };
      quiesceUnits = mkOption {
        type = types.nonEmptyListOf (types.strMatching ".+\\.(service|timer)");
        description = "Application units stopped before backup or restore.";
      };
      restartUnits = mkOption {
        type = types.nonEmptyListOf (types.strMatching ".+\\.(service|timer)");
        description = "Dependency-ordered units started after lifecycle work.";
      };
      verificationUnits = mkOption {
        type = types.nonEmptyListOf (types.strMatching ".+\\.(service|timer)");
        description = "Application units whose health is verified after lifecycle work.";
      };
    };
  };

  owner = path: user: group: mode: {
    inherit
      path
      user
      group
      mode
      ;
  };
  postgresqlDump = {
    kind = "postgresql";
    path = "${cfg.appdataRoot}/postgresql-dumps/latest.sql.gz";
    unit = "testbed-postgresql-dump.service";
  };
  mariadbDump = {
    kind = "mariadb";
    path = "${cfg.appdataRoot}/mariadb-dumps/latest.sql.gz";
    unit = "testbed-mariadb-dump.service";
  };
  application =
    {
      path,
      quiesceUnits,
      restartUnits ? quiesceUnits,
      verificationUnits ? quiesceUnits,
      excludedPaths ? [ ],
      databaseDumps ? [ ],
      user ? "root",
      group ? "testbed",
      mode ? "0750",
      ownership ? [ (owner path user group mode) ],
    }:
    {
      durablePaths = [ path ];
      inherit
        databaseDumps
        excludedPaths
        ownership
        quiesceUnits
        restartUnits
        verificationUnits
        ;
    };

  applications =
    optionalAttrs cfg.affine.enable {
      affine = application {
        path = cfg.affine.stateDir;
        quiesceUnits = [ "podman-affine.service" ];
        restartUnits = [
          "redis-affine.service"
          "affine-postgresql-password.service"
          "affine-postgresql-extensions.service"
          "podman-affine.service"
        ];
        databaseDumps = [ postgresqlDump ];
        ownership = [
          (owner cfg.affine.stateDir "root" "root" "0750")
          (owner "${cfg.affine.stateDir}/config" "root" "root" "0750")
          (owner "${cfg.affine.stateDir}/storage" "root" "root" "0750")
        ];
      };
    }
    // optionalAttrs cfg.firefly.enable {
      firefly = application {
        path = "${cfg.appdataRoot}/firefly-iii";
        user = "firefly-iii";
        group = "nginx";
        quiesceUnits = [
          "firefly-iii-cron.timer"
          "phpfpm-firefly-iii.service"
        ];
        restartUnits = [
          "phpfpm-firefly-iii.service"
          "firefly-iii-cron.timer"
        ];
        verificationUnits = [ "phpfpm-firefly-iii.service" ];
        databaseDumps = [ mariadbDump ];
      };
    }
    // optionalAttrs cfg.fizzy.enable {
      fizzy = application {
        path = cfg.fizzy.stateDir;
        user = "1000";
        group = "1000";
        quiesceUnits = [ "podman-fizzy.service" ];
        ownership = [
          (owner cfg.fizzy.stateDir "1000" "1000" "0750")
          (owner "${cfg.fizzy.stateDir}/storage" "1000" "1000" "0750")
        ];
      };
    }
    // optionalAttrs cfg.gitea.enable {
      gitea = application {
        path = "${cfg.appdataRoot}/gitea";
        user = "gitea";
        group = "gitea";
        quiesceUnits = [ "gitea.service" ];
        restartUnits = [
          "gitea.service"
        ]
        ++ optional cfg.gitea.oidc.enable "gitea-oidc-config.service";
        verificationUnits = [ "gitea.service" ];
        databaseDumps = [ postgresqlDump ];
      };
    }
    // {
      homebox = application {
        path = cfg.homebox.stateDir;
        user = "homebox";
        group = "homebox";
        quiesceUnits = [ "homebox.service" ];
        ownership = [
          (owner cfg.homebox.stateDir "homebox" "homebox" "0750")
          (owner "${cfg.homebox.stateDir}/data" "homebox" "homebox" "0750")
          (owner "${cfg.homebox.stateDir}/tmp" "homebox" "homebox" "0750")
        ];
      };
    }
    // optionalAttrs cfg.invoiceplane.enable {
      invoiceplane = application {
        path = cfg.invoiceplane.stateDir;
        user = "invoiceplane";
        group = "nginx";
        quiesceUnits = [ "phpfpm-invoiceplane.service" ];
        restartUnits = [
          "invoiceplane-mysql-password.service"
          "invoiceplane-prepare.service"
          "phpfpm-invoiceplane.service"
          "invoiceplane-bootstrap.service"
        ];
        verificationUnits = [ "phpfpm-invoiceplane.service" ];
        databaseDumps = [ mariadbDump ];
      };
    }
    // optionalAttrs cfg.kaneo.enable {
      kaneo = application {
        path = cfg.kaneo.stateDir;
        quiesceUnits = [ "podman-kaneo.service" ];
        restartUnits = [
          "kaneo-postgresql-password.service"
          "podman-kaneo.service"
        ];
        verificationUnits = [ "podman-kaneo.service" ];
        databaseDumps = [ postgresqlDump ];
      };
    }
    // optionalAttrs cfg.keeper.enable {
      keeper = application {
        path = cfg.keeper.stateDir;
        quiesceUnits = [
          "podman-keeper.service"
          "redis-keeper.service"
        ];
        restartUnits = [
          "redis-keeper.service"
          "keeper-postgresql-password.service"
          "podman-keeper.service"
        ];
        verificationUnits = [ "podman-keeper.service" ];
        databaseDumps = [ postgresqlDump ];
        ownership = [
          (owner cfg.keeper.stateDir "root" "testbed" "0750")
          (owner "${cfg.keeper.stateDir}/redis" "redis-keeper" "redis-keeper" "0750")
        ];
      };
    }
    // {
      listmonk = application {
        path = cfg.listmonk.stateDir;
        user = "listmonk";
        group = "listmonk";
        quiesceUnits = [ "listmonk.service" ];
        restartUnits = [
          "listmonk.service"
          "listmonk-oidc-config.service"
        ];
        verificationUnits = [ "listmonk.service" ];
        databaseDumps = [ postgresqlDump ];
      };
    }
    // optionalAttrs cfg.metube.enable {
      metube = application {
        path = cfg.metube.stateDir;
        user = "1000";
        quiesceUnits = [ "podman-metube.service" ];
        excludedPaths = [
          cfg.metube.downloadDir
          cfg.metube.tempDir
        ];
        ownership = [
          (owner cfg.metube.stateDir "1000" "testbed" "0750")
          (owner "${cfg.metube.stateDir}/state" "1000" "testbed" "0750")
        ];
      };
    }
    // optionalAttrs cfg.outline.enable {
      outline = application {
        path = cfg.outline.stateDir;
        quiesceUnits = [
          "podman-outline.service"
          "redis-outline.service"
        ];
        restartUnits = [
          "redis-outline.service"
          "outline-postgresql-password.service"
          "podman-outline.service"
        ];
        verificationUnits = [ "podman-outline.service" ];
        databaseDumps = [ postgresqlDump ];
        ownership = [
          (owner cfg.outline.stateDir "root" "testbed" "0750")
          (owner "${cfg.outline.stateDir}/redis" "redis-outline" "redis-outline" "0750")
        ];
      };
    }
    // optionalAttrs cfg.plane.enable {
      plane = application {
        path = cfg.plane.stateDir;
        quiesceUnits = [
          "podman-plane-admin.service"
          "podman-plane-api.service"
          "podman-plane-beat-worker.service"
          "podman-plane-live.service"
          "podman-plane-rabbitmq.service"
          "podman-plane-space.service"
          "podman-plane-web.service"
          "podman-plane-worker.service"
          "redis-plane.service"
        ];
        restartUnits = [
          "redis-plane.service"
          "podman-plane-rabbitmq.service"
          "plane-postgresql-password.service"
          "plane-rabbitmq-config.service"
          "plane-migrate.service"
          "podman-plane-api.service"
          "podman-plane-worker.service"
          "podman-plane-beat-worker.service"
          "podman-plane-live.service"
          "podman-plane-web.service"
          "podman-plane-admin.service"
          "podman-plane-space.service"
          "plane-admin-bootstrap.service"
        ];
        verificationUnits = [ "podman-plane-api.service" ];
        databaseDumps = [ postgresqlDump ];
        ownership = [
          (owner cfg.plane.stateDir "root" "testbed" "0750")
          (owner "${cfg.plane.stateDir}/rabbitmq" "999" "999" "0750")
          (owner "${cfg.plane.stateDir}/redis" "redis-plane" "redis-plane" "0750")
        ];
      };
    }
    // optionalAttrs cfg.postiz.enable {
      postiz = application {
        path = cfg.postiz.stateDir;
        quiesceUnits = [
          "podman-postiz.service"
          "podman-postiz-postgres.service"
          "podman-postiz-redis.service"
          "podman-postiz-temporal.service"
          "podman-postiz-temporal-elasticsearch.service"
          "podman-postiz-temporal-postgres.service"
        ];
        restartUnits = [
          "podman-postiz-postgres.service"
          "postiz-postgresql-password.service"
          "podman-postiz-redis.service"
          "podman-postiz-temporal-postgres.service"
          "postiz-temporal-postgresql-password.service"
          "podman-postiz-temporal-elasticsearch.service"
          "podman-postiz-temporal.service"
          "podman-postiz.service"
        ];
        verificationUnits = [ "podman-postiz.service" ];
        ownership = [
          (owner cfg.postiz.stateDir "root" "testbed" "0750")
          (owner "${cfg.postiz.stateDir}/config" "root" "testbed" "0750")
          (owner "${cfg.postiz.stateDir}/nginx" "100" "101" "0755")
          (owner "${cfg.postiz.stateDir}/nginx-logs" "100" "101" "0755")
          (owner "${cfg.postiz.stateDir}/postgresql" "999" "999" "0750")
          (owner "${cfg.postiz.stateDir}/redis" "999" "999" "0750")
          (owner "${cfg.postiz.stateDir}/temporal" "root" "testbed" "0750")
          (owner "${cfg.postiz.stateDir}/temporal/elasticsearch" "1000" "root" "0750")
          (owner "${cfg.postiz.stateDir}/temporal/postgresql" "999" "999" "0750")
          (owner "${cfg.postiz.stateDir}/uploads" "root" "testbed" "0750")
        ];
      };
    }
    // optionalAttrs cfg.stirlingPdf.enable {
      stirling-pdf = application {
        path = "${cfg.appdataRoot}/stirling-pdf";
        user = "stirling-pdf";
        group = "stirling-pdf";
        quiesceUnits = [ "stirling-pdf.service" ];
      };
    }
    // optionalAttrs cfg.sure.enable {
      sure = application {
        path = cfg.sure.stateDir;
        user = "1000";
        quiesceUnits = [
          "podman-sure-web.service"
          "podman-sure-worker.service"
          "redis-sure.service"
        ];
        restartUnits = [
          "redis-sure.service"
          "sure-postgresql-password.service"
          "podman-sure-web.service"
          "podman-sure-worker.service"
        ];
        verificationUnits = [ "podman-sure-web.service" ];
        databaseDumps = [ postgresqlDump ];
        ownership = [
          (owner cfg.sure.stateDir "1000" "testbed" "0750")
          (owner "${cfg.sure.stateDir}/redis" "redis-sure" "redis-sure" "0750")
          (owner "${cfg.sure.stateDir}/storage" "1000" "1000" "0750")
        ];
      };
    };

  declarations = attrValues recoveryCfg.applications;
  expectedApplications = attrNames applications;
  unitClaims = concatLists (
    mapAttrsToList (
      applicationName: declaration:
      map (unit: { inherit applicationName unit; }) (
        unique (declaration.quiesceUnits ++ declaration.restartUnits ++ declaration.verificationUnits)
      )
    ) recoveryCfg.applications
  );
  duplicateUnitClaims = filter (
    claim:
    count (
      candidate: candidate.unit == claim.unit && candidate.applicationName != claim.applicationName
    ) unitClaims > 0
  ) unitClaims;
  duplicateUnits = unique (map (claim: claim.unit) duplicateUnitClaims);
  pathIsUnderAppdata =
    path:
    let
      value = toString path;
    in
    value == toString cfg.appdataRoot || hasPrefix "${toString cfg.appdataRoot}/" value;
  pathIsAbsoluteAndClean =
    path:
    let
      value = toString path;
    in
    hasPrefix "/" value && !(hasInfix "/../" value) && !(hasSuffix "/.." value);
in
{
  options.fleet.testbed.recovery.applications = mkOption {
    type = types.attrsOf applicationType;
    default = optionalAttrs cfg.enable applications;
    description = "Evaluated recovery lifecycle facts for enabled stateful Testbed applications.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = attrNames recoveryCfg.applications == expectedApplications;
        message = "Testbed recovery applications must exactly match enabled stateful applications.";
      }
      {
        assertion = duplicateUnits == [ ];
        message = "Testbed recovery applications must not claim the same lifecycle unit: ${concatStringsSep ", " duplicateUnits}";
      }
      {
        assertion = all (declaration: all pathIsAbsoluteAndClean declaration.durablePaths) declarations;
        message = "Testbed recovery durable paths must be absolute and must not contain parent traversal.";
      }
      {
        assertion = all (declaration: all pathIsUnderAppdata declaration.durablePaths) declarations;
        message = "Testbed recovery durable paths must be within fleet.testbed.stack.appdataRoot.";
      }
      {
        assertion = all (declaration: all pathIsAbsoluteAndClean declaration.excludedPaths) declarations;
        message = "Testbed recovery excluded paths must be absolute and must not contain parent traversal.";
      }
      {
        assertion = all (
          declaration:
          all (
            rule:
            elem rule.path declaration.durablePaths
            || any (path: hasPrefix "${toString path}/" (toString rule.path)) declaration.durablePaths
          ) declaration.ownership
        ) declarations;
        message = "Testbed recovery ownership paths must be within an application's durable paths.";
      }
      {
        assertion = all (
          declaration: all (dump: pathIsUnderAppdata dump.path) declaration.databaseDumps
        ) declarations;
        message = "Testbed recovery database dump paths must be within fleet.testbed.stack.appdataRoot.";
      }
      {
        assertion =
          hasPrefix "/tmp/" (toString cfg.backup.restoreCheckTarget)
          || hasPrefix "/var/tmp/" (toString cfg.backup.restoreCheckTarget);
        message = "fleet.testbed.stack.backup.restoreCheckTarget must be below /tmp or /var/tmp.";
      }
    ];
  };
}
