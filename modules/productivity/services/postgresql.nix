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
  inherit (productivityLib) cfg appdata;
in
{
  config = mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      dataDir = "${appdata}/postgresql/${config.services.postgresql.package.psqlSchema}";
      ensureDatabases = [
        "affine"
        "shlink"
      ];
      ensureUsers = [
        {
          name = "affine";
          ensureDBOwnership = true;
        }
        {
          name = "shlink";
          ensureDBOwnership = true;
        }
      ];
      extensions = postgresqlPackages: [ postgresqlPackages.pgvector ];
    };
  };
}
