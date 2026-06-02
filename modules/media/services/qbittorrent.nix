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
  inherit (mediaLib) cfg appdata mediaRoot qbittorrentConfigScript;
 in
{
  config = mkIf cfg.enable {
virtualisation.oci-containers.containers = {
  media-qbittorrent = {
    image = cfg.qbittorrent.image;
    pull = "missing";

    dependsOn = [ "media-gluetun" ];

    environment = {
      PGID = toString config.users.groups.media.gid;
      PUID = toString config.users.users.qbittorrent.uid;
      TZ = config.time.timeZone;
      UMASK = "0077";
      WEBUI_PORT = toString cfg.ports.qbittorrent;
    };

    volumes = [
      "${appdata}/qbittorrent:/config"
      "${cfg.downloads.incomplete}:${cfg.downloads.incomplete}"
      "${mediaRoot}:${mediaRoot}"
    ];

    extraOptions = [
      "--network=container:media-gluetun"
    ];
  };
};

systemd.services = {
  podman-media-qbittorrent = {
    after = [
      "podman-media-gluetun.service"
      "${utils.escapeSystemdPath mediaRoot}.mount"
    ];
    bindsTo = [ "podman-media-gluetun.service" ];
    partOf = [ "podman-media-gluetun.service" ];
    preStart = "${qbittorrentConfigScript}";
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
