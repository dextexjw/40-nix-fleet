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
  inherit (productivityLib) cfg;
in
{
  config = mkIf cfg.enable {
    services.iperf3 = {
      enable = true;
      openFirewall = false;
      port = cfg.ports.iperf3;
    };
  };
}
