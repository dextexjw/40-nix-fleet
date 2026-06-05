{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  mediaLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (mediaLib) cfg gluetunCfg;
in
{
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      cfg.ports.audiobookshelf
      cfg.ports.bazarr
      cfg.ports.jellyfin
      cfg.ports.kavita
      cfg.ports.prowlarr
      cfg.ports.qbittorrent
      cfg.ports.radarr
      cfg.ports.sabnzbd
      cfg.ports.seerr
      cfg.ports.sonarr
    ]
    ++ optional gluetunCfg.webUi.enable gluetunCfg.webUi.port;

    # --------------------------------------------------------------------------
  };
}
