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
services.ntfy-sh = {
  enable = true;
  settings = {
    base-url = "http://${serviceHosts.ntfy}";
    listen-http = "0.0.0.0:${toString cfg.ports.ntfy}";
    auth-file = "${appdata}/ntfy/user.db";
    attachment-cache-dir = "${appdata}/ntfy/attachments";
    cache-file = "${appdata}/ntfy/cache.db";
  };
};

systemd.services.ntfy-sh.serviceConfig = {
  DynamicUser = mkForce false;
  ReadWritePaths = [ "${appdata}/ntfy" ];
  StateDirectory = mkForce "";
};
  };
}
