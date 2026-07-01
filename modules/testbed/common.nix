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

    systemd.tmpfiles.rules = [
      "d ${appdata} 0755 root root - -"
      "d ${cfg.fizzy.stateDir} 0750 1000 1000 - -"
      "d ${cfg.fizzy.stateDir}/storage 0750 1000 1000 - -"
      "d ${cfg.homebox.stateDir} 0750 homebox homebox - -"
      "d ${cfg.homebox.stateDir}/data 0750 homebox homebox - -"
      "d ${cfg.homebox.stateDir}/tmp 0750 homebox homebox - -"
      "d ${cfg.kaneo.stateDir} 0750 root testbed - -"
      "d ${cfg.kaneo.stateDir}/tmp 0750 root testbed - -"
      "d ${cfg.keeper.stateDir} 0750 root testbed - -"
      "z ${cfg.keeper.stateDir} 0750 root testbed - -"
      "d ${cfg.keeper.stateDir}/redis 0750 redis-keeper redis-keeper - -"
      "z ${cfg.keeper.stateDir}/redis 0750 redis-keeper redis-keeper - -"
      "d ${cfg.listmonk.stateDir} 0750 listmonk listmonk - -"
      "d ${cfg.listmonk.stateDir}/uploads 0750 listmonk listmonk - -"
      "d ${cfg.plane.stateDir} 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/api 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/beat-worker 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/migrator 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/logs/worker 0750 root testbed - -"
      "d ${cfg.plane.stateDir}/rabbitmq 0750 999 999 - -"
      "d ${cfg.plane.stateDir}/redis 0750 redis-plane redis-plane - -"
      "z ${cfg.plane.stateDir}/redis 0750 redis-plane redis-plane - -"
      "d ${appdata}/postgresql 0750 postgres postgres - -"
      "z ${appdata}/postgresql 0750 postgres postgres - -"
      "d ${appdata}/postgresql/${config.services.postgresql.package.psqlSchema} 0750 postgres postgres - -"
      "z ${appdata}/postgresql/${config.services.postgresql.package.psqlSchema} 0750 postgres postgres - -"
      "d ${appdata}/postgresql-dumps 0700 postgres postgres - -"
    ];

    environment.systemPackages = [
      config.services.postgresql.package
      pkgs.restic
    ];
  };
}
