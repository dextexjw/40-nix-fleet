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
services.radarr = {
  enable = true;
  user = "radarr";
  group = "media";
  dataDir = "${appdata}/radarr";
  settings.server.port = cfg.ports.radarr;
};

systemd.services = {
  radarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
  radarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
};
  };
}
