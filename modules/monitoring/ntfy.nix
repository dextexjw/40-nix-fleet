{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.monitoring.stack;
in
{
  config = mkIf (cfg.enable && cfg.ntfy.enable) {
    services.ntfy-sh = {
      enable = true;
      settings = {
        attachment-cache-dir = "${cfg.ntfy.stateDir}/attachments";
        auth-file = "${cfg.ntfy.stateDir}/user.db";
        base-url = cfg.ntfy.publicUrl;
        cache-file = "${cfg.ntfy.stateDir}/cache.db";
        listen-http = "0.0.0.0:${toString cfg.ports.ntfy}";
        upstream-base-url = cfg.ntfy.upstreamBaseUrl;
      };
    };

    systemd.services.ntfy-sh.serviceConfig = {
      DynamicUser = mkForce false;
      ReadWritePaths = [ cfg.ntfy.stateDir ];
      StateDirectory = mkForce "";
    };
  };
}
