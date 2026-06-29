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
  gatewayOnlyTCPPorts = unique [
    80
    cfg.ports.affine
    cfg.ports.forgejo
    cfg.ports.garageS3
    cfg.ports.garageWeb
    cfg.ports.gitea
    cfg.ports.memos
    cfg.ports.openspeedtest
    cfg.ports.rustfsApi
    cfg.ports.rustfsConsole
    cfg.ports.searxng
    cfg.ports.shlink
    cfg.ports.shlinkWeb
    cfg.ports.stirlingPdf
    cfg.ports.syncthing
    cfg.ports.vaultwarden
  ];
  mkGatewayAccept =
    port:
    concatMapStringsSep "\n" (
      gatewayAddress:
      "iptables -A nixos-fw -p tcp -s ${gatewayAddress} --dport ${toString port} -j nixos-fw-accept"
    ) cfg.onDemandLauncher.gatewayAddresses;
in
{
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      cfg.ports.iperf3
      21115
      21116
      21117
      21118
      21119
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

    networking.firewall.extraCommands = concatStringsSep "\n" (map mkGatewayAccept gatewayOnlyTCPPorts);
  };
}
