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
  inherit (mediaLib) cfg;
in
{
  config = mkIf cfg.enable {
    services.flaresolverr = {
      enable = true;
      port = 8191;
    };
  };
}
