{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg appdata serviceHosts;
in
{
  config = mkIf cfg.enable {
    services.privatebin = {
      enable = true;
      dataDir = "${appdata}/privatebin";
      enableNginx = true;
      virtualHost = serviceHosts.privatebin;
      settings = {
        main = {
          name = "Fleet PrivateBin";
          discussion = false;
          fileupload = false;
          qrcode = true;
          sizelimit = 10485760;
        };
        expire.default = "1week";
      };
    };
  };
}
