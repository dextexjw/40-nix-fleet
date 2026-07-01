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
      (mkGatewayAccept cfg.ports.fizzy)
      (mkGatewayAccept cfg.ports.homebox)
      (mkGatewayAccept cfg.ports.kaneo)
      (mkGatewayAccept cfg.ports.keeper)
      (mkGatewayAccept cfg.ports.listmonk)
      (mkGatewayAccept cfg.ports.mailpit)
      (mkGatewayAccept cfg.ports.mailpitSmtp)
    ];
  };
}
