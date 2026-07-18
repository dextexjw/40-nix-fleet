{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  testbedLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg;
  mkGatewayAccept =
    port:
    concatMapStringsSep "\n" (
      gatewayAddress:
      "iptables -A nixos-fw -p tcp -s ${gatewayAddress} --dport ${toString port} -j nixos-fw-accept"
    ) cfg.gatewayAddresses;
in
{
  config = mkIf cfg.enable {
    networking.firewall.extraCommands = concatStringsSep "\n" [
      (mkGatewayAccept cfg.ports.affine)
      (mkGatewayAccept cfg.ports.firefly)
      (mkGatewayAccept cfg.ports.fizzy)
      (mkGatewayAccept cfg.ports.gitea)
      (mkGatewayAccept cfg.ports.homebox)
      (mkGatewayAccept cfg.ports.invoiceplane)
      (mkGatewayAccept cfg.ports.kaneo)
      (mkGatewayAccept cfg.ports.karakeep)
      (mkGatewayAccept cfg.ports.keeper)
      (mkGatewayAccept cfg.ports.listmonk)
      (mkGatewayAccept cfg.ports.mailpit)
      (mkGatewayAccept cfg.ports.mailpitSmtp)
      (mkGatewayAccept cfg.ports.metube)
      (mkGatewayAccept cfg.ports.outline)
      (mkGatewayAccept cfg.ports.plane)
      (mkGatewayAccept cfg.ports.postiz)
      (mkGatewayAccept cfg.ports.stirlingPdf)
      (mkGatewayAccept cfg.ports.sure)
    ];
  };
}
