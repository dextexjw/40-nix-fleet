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
services.gitea = {
  enable = true;
  appName = "Fleet Git";
  lfs.enable = true;
  stateDir = "${appdata}/gitea";
  database = {
    type = "postgres";
    createDatabase = true;
  };
  dump = {
    enable = true;
    backupDir = "${appdata}/gitea/dump";
    type = "tar.zst";
  };
  settings = {
    repository.DEFAULT_BRANCH = "main";
    server = {
      DOMAIN = serviceHosts.gitea;
      HTTP_ADDR = "0.0.0.0";
      HTTP_PORT = cfg.ports.gitea;
      ROOT_URL = "http://${serviceHosts.gitea}/";
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
