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
  inherit (mediaLib) cfg appdata mediaRoot;
in
{
  config = mkIf cfg.enable {
    services.sonarr = {
      enable = true;
      user = "sonarr";
      group = "media";
      dataDir = "${appdata}/sonarr";
      settings.server.port = cfg.ports.sonarr;
    };

    systemd.services = {
      sonarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sonarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
    };
  };
}
