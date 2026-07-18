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
  inherit (testbedLib) cfg appdata;
in
{
  config = mkIf cfg.enable {
    boot.supportedFilesystems.cifs = true;

    users.groups.testbed = { };
    users.groups.stirling-pdf = { };

    users.users.stirling-pdf = {
      isSystemUser = true;
      group = "stirling-pdf";
      home = "${appdata}/stirling-pdf";
    };

    systemd.tmpfiles.rules = [
      "d ${appdata} 0755 root root - -"
      "d ${cfg.affine.stateDir} 0750 root root - -"
      "z ${cfg.affine.stateDir} 0750 root root - -"
      "d ${cfg.affine.stateDir}/config 0750 root root - -"
      "z ${cfg.affine.stateDir}/config 0750 root root - -"
      "d ${cfg.affine.stateDir}/storage 0750 root root - -"
      "z ${cfg.affine.stateDir}/storage 0750 root root - -"
      "d ${appdata}/firefly-iii 0750 firefly-iii nginx - -"
      "z ${appdata}/firefly-iii 0750 firefly-iii nginx - -"
      "d ${cfg.fizzy.stateDir} 0750 1000 1000 - -"
      "d ${cfg.fizzy.stateDir}/storage 0750 1000 1000 - -"
      "d ${appdata}/gitea 0750 gitea gitea - -"
      "z ${appdata}/gitea 0750 gitea gitea - -"
      "d ${cfg.homebox.stateDir} 0750 homebox homebox - -"
      "d ${cfg.homebox.stateDir}/data 0750 homebox homebox - -"
      "d ${cfg.homebox.stateDir}/tmp 0750 homebox homebox - -"
      "d ${cfg.invoiceplane.stateDir} 0750 invoiceplane nginx - -"
      "z ${cfg.invoiceplane.stateDir} 0750 invoiceplane nginx - -"
      "d ${cfg.kaneo.stateDir} 0750 root testbed - -"
      "d ${cfg.kaneo.stateDir}/tmp 0750 root testbed - -"
      "d ${cfg.karakeep.stateDir} 0711 root testbed - -"
      "z ${cfg.karakeep.stateDir} 0711 root testbed - -"
      "d ${cfg.karakeep.stateDir}/data 0750 root testbed - -"
      "d ${cfg.karakeep.stateDir}/meilisearch 0750 1000 1000 - -"
      "d ${cfg.keeper.stateDir} 0750 root testbed - -"
      "z ${cfg.keeper.stateDir} 0750 root testbed - -"
      "d ${cfg.keeper.stateDir}/redis 0750 redis-keeper redis-keeper - -"
      "z ${cfg.keeper.stateDir}/redis 0750 redis-keeper redis-keeper - -"
      "d ${cfg.listmonk.stateDir} 0750 listmonk listmonk - -"
      "d ${cfg.listmonk.stateDir}/uploads 0750 listmonk listmonk - -"
      "d ${cfg.metube.stateDir} 0750 1000 testbed - -"
      "z ${cfg.metube.stateDir} 0750 1000 testbed - -"
      "d ${cfg.metube.stateDir}/state 0750 1000 testbed - -"
      "z ${cfg.metube.stateDir}/state 0750 1000 testbed - -"
      "d ${cfg.metube.tempDir} 0770 1000 testbed - -"
      "z ${cfg.metube.tempDir} 0770 1000 testbed - -"
      "d ${cfg.outline.stateDir} 0750 root testbed - -"
      "d ${cfg.outline.stateDir}/redis 0750 redis-outline redis-outline - -"
      "z ${cfg.outline.stateDir}/redis 0750 redis-outline redis-outline - -"
      "d ${cfg.plane.stateDir} 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/api 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/beat-worker 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/migrator 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/worker 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/rabbitmq 0750 999 999 - -"
      "d ${cfg.plane.stateDir}/redis 0750 redis-plane redis-plane - -"
      "z ${cfg.plane.stateDir}/redis 0750 redis-plane redis-plane - -"
      "d ${cfg.postiz.stateDir} 0750 root testbed - -"
      "d ${cfg.postiz.stateDir}/config 0750 root testbed - -"
      "d ${cfg.postiz.stateDir}/postgresql 0750 999 999 - -"
      "d ${cfg.postiz.stateDir}/redis 0750 999 999 - -"
      "d ${cfg.postiz.stateDir}/temporal 0750 root testbed - -"
      "d ${cfg.postiz.stateDir}/temporal/elasticsearch 0750 1000 root - -"
      "d ${cfg.postiz.stateDir}/temporal/postgresql 0750 999 999 - -"
      "d ${cfg.postiz.stateDir}/uploads 0750 root testbed - -"
      "d ${appdata}/stirling-pdf 0750 stirling-pdf stirling-pdf - -"
      "z ${appdata}/stirling-pdf 0750 stirling-pdf stirling-pdf - -"
      "d ${cfg.sure.stateDir} 0750 1000 testbed - -"
      "z ${cfg.sure.stateDir} 0750 1000 testbed - -"
      "d ${cfg.sure.stateDir}/redis 0750 redis-sure redis-sure - -"
      "z ${cfg.sure.stateDir}/redis 0750 redis-sure redis-sure - -"
      "d ${cfg.sure.stateDir}/storage 0750 1000 1000 - -"
      "d ${appdata}/postgresql 0750 postgres postgres - -"
      "z ${appdata}/postgresql 0750 postgres postgres - -"
      "d ${appdata}/postgresql/${config.services.postgresql.package.psqlSchema} 0750 postgres postgres - -"
      "z ${appdata}/postgresql/${config.services.postgresql.package.psqlSchema} 0750 postgres postgres - -"
      "d ${appdata}/postgresql-dumps 0700 postgres postgres - -"
      "d ${appdata}/mariadb-dumps 0700 root root - -"
    ];

    environment.systemPackages = [
      config.services.mysql.package
      config.services.postgresql.package
      pkgs.restic
    ];
  };
}
