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
    sabnzbdConfigScript
    ;
in
{
  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers = {
      media-sabnzbd = {
        image = cfg.sabnzbd.image;
        pull = "missing";

        dependsOn = [ "media-gluetun" ];

        environment = {
          PGID = toString config.users.groups.media.gid;
          PUID = toString config.users.users.sabnzbd.uid;
          TZ = config.time.timeZone;
          UMASK = "0077";
        };

        volumes = [
          "${appdata}/sabnzbd:/config"
          "${cfg.downloads.incomplete}:${cfg.downloads.incomplete}"
          "${mediaRoot}:${mediaRoot}"
        ];

        extraOptions = [
          "--network=container:media-gluetun"
        ];
      };
    };

    systemd.services = {
      podman-media-sabnzbd = {
        after = [
          "podman-media-gluetun.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        bindsTo = [ "podman-media-gluetun.service" ];
        partOf = [ "podman-media-gluetun.service" ];
        preStart = "${sabnzbdConfigScript}";
        requires = [
          "podman-media-gluetun.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };
    };
  };
}
