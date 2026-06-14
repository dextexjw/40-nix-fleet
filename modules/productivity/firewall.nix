{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg;
in
{
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      80
      cfg.ports.affine
      cfg.ports.forgejo
      cfg.ports.garageS3
      cfg.ports.garageWeb
      cfg.ports.gitea
      cfg.ports.iperf3
      cfg.ports.memos
      cfg.ports.ntfy
      cfg.ports.openspeedtest
      21115
      21116
      21117
      21118
      21119
      cfg.ports.rustfsApi
      cfg.ports.rustfsConsole
      cfg.ports.searxng
      cfg.ports.shlink
      cfg.ports.shlinkWeb
      cfg.ports.stirlingPdf
      cfg.ports.syncthing
      cfg.ports.vaultwarden
    ]
    ++ optionals cfg.netbootxyz.openFirewall [
      cfg.netbootxyz.assetPort
      cfg.netbootxyz.webUiPort
    ];
    networking.firewall.allowedUDPPorts = [
      cfg.ports.iperf3
      21116
    ]
    ++ optionals cfg.netbootxyz.openFirewall [
      cfg.netbootxyz.tftpPort
    ];
  };
}
