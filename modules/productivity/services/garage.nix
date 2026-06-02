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
  inherit (productivityLib) cfg appdata garageEnvironmentFile secretPath serviceHosts;
 in
{
  config = mkIf cfg.enable {
services.garage = {
  enable = true;
  environmentFile = garageEnvironmentFile;
  package = pkgs.garage;
  settings = {
    replication_factor = 1;
    consistency_mode = "consistent";
    metadata_dir = "${appdata}/garage/meta";
    data_dir = "${appdata}/garage/data";
    metadata_snapshots_dir = "${appdata}/garage/snapshots";
    db_engine = "lmdb";
    rpc_bind_addr = "0.0.0.0:${toString cfg.ports.garageRpc}";
    rpc_public_addr = "127.0.0.1:${toString cfg.ports.garageRpc}";
    rpc_secret_file = secretPath "garage-rpc-secret";
    s3_api = {
      api_bind_addr = "0.0.0.0:${toString cfg.ports.garageS3}";
      root_domain = ".${serviceHosts.garage}";
      s3_region = "garage";
    };
    s3_web = {
      bind_addr = "0.0.0.0:${toString cfg.ports.garageWeb}";
      root_domain = ".${serviceHosts.garageWeb}";
    };
    admin = {
      admin_token_file = secretPath "garage-admin-token";
      api_bind_addr = "127.0.0.1:${toString cfg.ports.garageAdmin}";
      metrics_require_token = true;
      metrics_token_file = secretPath "garage-metrics-token";
    };
  };
};

systemd.services.garage.serviceConfig = {
  DynamicUser = mkForce false;
  User = "garage";
  Group = "garage";
};
  };
}
