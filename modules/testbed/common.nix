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
    users.groups.testbed = { };

    systemd.tmpfiles.rules = [
      "d ${appdata} 0755 root root - -"
      "d ${cfg.fizzy.stateDir} 0750 1000 1000 - -"
      "d ${cfg.fizzy.stateDir}/storage 0750 1000 1000 - -"
      "d ${cfg.listmonk.stateDir} 0750 listmonk listmonk - -"
      "d ${cfg.listmonk.stateDir}/uploads 0750 listmonk listmonk - -"
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
