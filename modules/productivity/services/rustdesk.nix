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
  inherit (productivityLib) cfg appdata serviceHosts;
  stateDir = "${appdata}/rustdesk";
in
{
  config = mkIf cfg.enable {
    services.rustdesk-server = {
      enable = true;
      openFirewall = false;
      relay.enable = true;
      signal = {
        enable = true;
        relayHosts = [ serviceHosts.rustdesk ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 rustdesk rustdesk - -"
    ];

    systemd.services.rustdesk-signal = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        DynamicUser = mkForce false;
        ReadWritePaths = [ stateDir ];
        StateDirectory = mkForce "";
        WorkingDirectory = mkForce stateDir;
      };
    };

    systemd.services.rustdesk-relay = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        DynamicUser = mkForce false;
        ReadWritePaths = [ stateDir ];
        StateDirectory = mkForce "";
        WorkingDirectory = mkForce stateDir;
      };
    };
  };
}
