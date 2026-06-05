{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.monitoring.nodeExporter;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.monitoring.nodeExporter = {
    enable = mkEnableOption "Prometheus Node Exporter";

    port = mkOption {
      type = types.port;
      default = 9100;
      description = "Port for Node Exporter metrics";
    };

    enabledCollectors = mkOption {
      type = types.listOf types.str;
      default = [
        "systemd"
        "textfile"
        "filesystem"
        "loadavg"
        "meminfo"
        "netdev"
        "stat"
      ];
      description = "List of enabled collectors";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # NODE EXPORTER SERVICE
    # --------------------------------------------------------------------------

    services.prometheus.exporters.node = {
      enable = true;
      port = cfg.port;
      enabledCollectors = cfg.enabledCollectors;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
