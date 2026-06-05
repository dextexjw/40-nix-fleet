{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  mediaLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (mediaLib) cfg appdata;
in
{
  config = mkIf cfg.enable {
    services.prowlarr = {
      enable = true;
      dataDir = "${appdata}/prowlarr";
      settings.server.port = cfg.ports.prowlarr;
    };

    systemd.services = {
      prowlarr.requires = [ "${utils.escapeSystemdPath "/var/lib/private/prowlarr"}.mount" ];
      prowlarr.after = [ "${utils.escapeSystemdPath "/var/lib/private/prowlarr"}.mount" ];
      prowlarr.serviceConfig.StateDirectoryMode = mkForce "0700";
    };
  };
}
