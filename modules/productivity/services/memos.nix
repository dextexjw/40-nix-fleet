{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib)
    cfg
    appdata
    memosGid
    memosUid
    serviceHosts
    ;
in
{
  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.memos = {
      image = "docker.io/neosmemo/memos@sha256:62896725e9f84cc1c6afa6319f8ac759bc7d64670a9e003ef0844c12d345eadb";
      pull = "missing";

      environment = {
        MEMOS_ADDR = "0.0.0.0";
        MEMOS_DATA = "/var/opt/memos";
        MEMOS_DRIVER = "sqlite";
        MEMOS_GID = toString memosGid;
        MEMOS_INSTANCE_URL = "https://${serviceHosts.memos}";
        MEMOS_MODE = "prod";
        MEMOS_PORT = toString cfg.ports.memos;
        MEMOS_UID = toString memosUid;
      };

      extraOptions = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--user=${toString memosUid}:${toString memosGid}"
      ];

      ports = [
        "0.0.0.0:${toString cfg.ports.memos}:${toString cfg.ports.memos}/tcp"
      ];

      volumes = [
        "${appdata}/memos:/var/opt/memos"
      ];
    };

    systemd.services.podman-memos = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };
  };
}
