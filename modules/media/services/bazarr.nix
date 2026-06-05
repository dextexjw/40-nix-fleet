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
    services.bazarr = {
      enable = true;
      user = "bazarr";
      group = "media";
      dataDir = "${appdata}/bazarr";
      listenPort = cfg.ports.bazarr;
    };

    systemd.services = {
      bazarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      bazarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
    };
  };
}
