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
services.forgejo = {
  enable = true;
  package = pkgs.forgejo;
  lfs.enable = true;
  stateDir = "${appdata}/forgejo";
  database = {
    type = "postgres";
    createDatabase = true;
  };
  dump = {
    enable = true;
    backupDir = "${appdata}/forgejo/dump";
    type = "tar.zst";
  };
  settings = {
    DEFAULT.APP_NAME = "Fleet Forgejo";
    repository.DEFAULT_BRANCH = "main";
    server = {
      DOMAIN = serviceHosts.forgejo;
      HTTP_ADDR = "0.0.0.0";
      HTTP_PORT = cfg.ports.forgejo;
      ROOT_URL = "http://${serviceHosts.forgejo}/";
      SSH_PORT = 22;
    };
    service = {
      DISABLE_REGISTRATION = true;
      REQUIRE_SIGNIN_VIEW = false;
    };
  };
};
  };
}
