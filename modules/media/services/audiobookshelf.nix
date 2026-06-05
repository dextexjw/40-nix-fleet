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
  inherit (mediaLib)
    cfg
    appdata
    mediaRoot
    audiobookshelfExecStart
    ;
in
{
  config = mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      user = "audiobookshelf";
      group = "media";
      dataDir = "audiobookshelf";
      host = "0.0.0.0";
      port = cfg.ports.audiobookshelf;
    };

    systemd.services = {
      audiobookshelf.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      audiobookshelf.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      audiobookshelf.serviceConfig = {
        ExecStart = mkForce audiobookshelfExecStart;
        StateDirectory = mkForce "";
        WorkingDirectory = mkForce "${appdata}/audiobookshelf";
      };
    };
  };
}
