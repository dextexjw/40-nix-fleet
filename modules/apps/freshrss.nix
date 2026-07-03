{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.apps.freshrss;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.freshrss = {
    enable = mkEnableOption "FreshRSS RSS aggregator";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for FreshRSS web interface";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/freshrss";
      description = "Data directory for FreshRSS configuration";
    };

    timezone = mkOption {
      type = types.str;
      default = "Etc/UTC";
      description = "Timezone for FreshRSS container";
    };

    user = mkOption {
      type = types.str;
      default = "freshrss";
      description = "User to run FreshRSS container as";
    };

    group = mkOption {
      type = types.str;
      default = "freshrss";
      description = "Group to run FreshRSS container as";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # USER AND GROUP SETUP
    # --------------------------------------------------------------------------

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.${cfg.group} = { };

    # --------------------------------------------------------------------------
    # DATA DIRECTORY SETUP
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    # --------------------------------------------------------------------------
    # FRESHRSS CONTAINER
    # --------------------------------------------------------------------------

    virtualisation.oci-containers.containers.freshrss = {
      image = "lscr.io/linuxserver/freshrss@sha256:b67eb8dbe1e6944ce45f761645858b25b2a852d5dd3e5e49f001bd5cf2534350";
      pull = "missing";

      ports = [
        "${toString cfg.port}:80"
      ];

      environment = {
        PUID = toString config.users.users.${cfg.user}.uid;
        PGID = toString config.users.groups.${cfg.group}.gid;
        TZ = cfg.timezone;
      };

      volumes = [
        "${cfg.dataDir}:/config"
      ];

    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # --------------------------------------------------------------------------
    # SYSTEMD SERVICE DEPENDENCIES
    # --------------------------------------------------------------------------

    systemd.services."podman-freshrss" = {
      requires = [ "podman.service" ];
      after = [ "podman.service" ];
    };
  };
}
