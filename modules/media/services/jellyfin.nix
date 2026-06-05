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
    services.jellyfin = {
      enable = true;
      openFirewall = true;
      user = "jellyfin";
      group = "media";
      dataDir = "${appdata}/jellyfin";
      configDir = "${appdata}/jellyfin/config";
      cacheDir = "${appdata}/jellyfin/cache";
      logDir = "${appdata}/jellyfin/log";
    };

    systemd.services = {
      jellyfin.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      jellyfin.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      jellyfin.environment = mkIf (cfg.jellyfin.publishedServerUrl != null) {
        JELLYFIN_PublishedServerUrl = cfg.jellyfin.publishedServerUrl;
      };
    };
  };
}
