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
    networking.firewall.extraCommands = mkGatewayAccept cfg.ports.listmonk;
  };
}
