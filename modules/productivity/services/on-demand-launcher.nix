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
  inherit (productivityLib) cfg;

  launcherCfg = cfg.onDemandLauncher;

  bundleType = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        default = "";
        description = "Short app description shown in the dashboard.";
      };

      health = {
        headers = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "HTTP headers sent to the app health check.";
        };

        okStatuses = mkOption {
          type = types.listOf types.ints.positive;
          default = [
            200
            204
            301
            302
            303
            307
            308
          ];
          description = "HTTP statuses that mean the app is ready.";
        };

        pollSeconds = mkOption {
          type = types.ints.positive;
          default = 2;
          description = "Seconds between readiness probes after starting an app.";
        };

        requestTimeoutSeconds = mkOption {
          type = types.ints.positive;
          default = 5;
          description = "Per-request health-check timeout.";
        };

        url = mkOption {
          type = types.str;
          description = "HTTP URL used by the dashboard to check readiness.";
        };

        waitSeconds = mkOption {
          type = types.ints.positive;
          default = 120;
          description = "Maximum seconds to wait for an app to become ready.";
        };
      };

      name = mkOption {
        type = types.str;
        description = "Display name.";
      };

      startUnits = mkOption {
        type = types.listOf types.str;
        description = "Systemd units started, in order, when launching the app.";
      };

      statusUnits = mkOption {
        type = types.listOf types.str;
        description = "Systemd units used to summarize app state.";
      };

      stopUnits = mkOption {
        type = types.listOf types.str;
        description = "Systemd units stopped, in order, when shutting down the app.";
      };

      url = mkOption {
        type = types.str;
        description = "Canonical app URL opened after readiness succeeds.";
      };
    };
  };

  appList = mapAttrsToList (id: bundle: {
    inherit id;
    inherit (bundle)
      description
      name
      url
      ;
    start_units = bundle.startUnits;
    status_units = bundle.statusUnits;
    stop_units = bundle.stopUnits;
    health = {
      inherit (bundle.health) headers url;
      ok_statuses = bundle.health.okStatuses;
      poll_seconds = bundle.health.pollSeconds;
      request_timeout_seconds = bundle.health.requestTimeoutSeconds;
      wait_seconds = bundle.health.waitSeconds;
    };
  }) launcherCfg.bundles;

  systemctlAllowedUnits = unique (
    launcherCfg.blockedUnits
    ++ concatMap (bundle: bundle.startUnits ++ bundle.statusUnits ++ bundle.stopUnits) (
      attrValues launcherCfg.bundles
    )
  );
  systemctlAllowedActions = [
    "reset-failed"
    "start"
    "stop"
  ];

  systemctlHelper = pkgs.writeShellScript "on-demand-apps-systemctl" ''
    set -euo pipefail

    if [ "$#" -ne 2 ]; then
      echo "usage: on-demand-apps-systemctl ACTION UNIT" >&2
      exit 2
    fi

    action="$1"
    unit="$2"

    case "$action" in
      reset-failed|start|stop) ;;
      *)
        echo "refusing unsupported systemctl action: $action" >&2
        exit 2
        ;;
    esac

    case "$unit" in
      ${concatStringsSep "|" systemctlAllowedUnits}) ;;
      *)
        echo "refusing unit outside on-demand allow-list: $unit" >&2
        exit 2
        ;;
    esac

    exec ${pkgs.systemd}/bin/systemctl "$action" "$unit"
  '';

  launcherConfig = pkgs.writeText "on-demand-apps-dashboard.json" (
    builtins.toJSON {
      apps = appList;
      allowed_groups = launcherCfg.allowedGroups;
      auth_header = launcherCfg.authHeader;
      auth_groups_header = launcherCfg.authGroupsHeader;
      blocked_units = launcherCfg.blockedUnits;
      listen = {
        address = launcherCfg.bindAddress;
        inherit (launcherCfg) port;
      };
      maintenance_lock = launcherCfg.maintenanceLock;
      require_allowed_group = launcherCfg.requireAllowedGroup;
      require_auth_header = launcherCfg.requireAuthHeader;
      systemctl_helper = systemctlHelper;
    }
  );
in
{
  options.fleet.productivity.stack.onDemandLauncher = {
    allowedGroups = mkOption {
      type = types.listOf types.str;
      default = [
        "fleet-admins"
        "productivity-users"
      ];
      description = "Authentik groups allowed to use launcher control pages and actions.";
    };

    authGroupsHeader = mkOption {
      type = types.str;
      default = "X-authentik-groups";
      description = "Forward-auth response header containing Authentik group names.";
    };

    authHeader = mkOption {
      type = types.str;
      default = "X-authentik-username";
      description = "Forward-auth response header required for browser control pages and actions.";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address for the on-demand apps dashboard to listen on.";
    };

    blockedUnits = mkOption {
      type = types.listOf types.str;
      default = [
        "affine-postgresql-extensions.service"
        "affine-postgresql-password.service"
        "firefly-iii-setup.service"
        "gitea-oidc-config.service"
        "nixos-upgrade.service"
        "productivity-appdata-backup.service"
        "productivity-appdata-restore-check.service"
        "productivity-mariadb-dump.service"
        "productivity-memos-sqlite-backup.service"
        "productivity-postgresql-dump.service"
      ];
      description = "Units that block start/stop actions while active.";
    };

    bundles = mkOption {
      type = types.attrsOf bundleType;
      default = {
        affine = {
          name = "AFFiNE";
          description = "Collaborative docs and whiteboards";
          url = "https://${cfg.serviceHosts.affine}/";
          startUnits = [
            "redis-affine.service"
            "podman-affine.service"
          ];
          stopUnits = [
            "podman-affine.service"
            "redis-affine.service"
          ];
          statusUnits = [
            "podman-affine.service"
            "redis-affine.service"
          ];
          health = {
            headers.Host = cfg.serviceHosts.affine;
            url = "http://127.0.0.1:${toString cfg.ports.affine}/";
            waitSeconds = 180;
          };
        };

        firefly = {
          name = "Firefly III";
          description = "Personal finance";
          url = "https://${cfg.serviceHosts.firefly}/";
          startUnits = [
            "phpfpm-firefly-iii.service"
            "firefly-iii-cron.timer"
          ];
          stopUnits = [
            "firefly-iii-cron.timer"
            "firefly-iii-cron.service"
            "phpfpm-firefly-iii.service"
          ];
          statusUnits = [
            "phpfpm-firefly-iii.service"
            "firefly-iii-cron.timer"
          ];
          health = {
            headers.Host = cfg.serviceHosts.firefly;
            okStatuses = [
              200
              301
              302
              303
              307
              308
            ];
            url = "http://127.0.0.1/";
            waitSeconds = 90;
          };
        };

        gitea = {
          name = "Gitea";
          description = "Git repositories";
          url = "https://${cfg.serviceHosts.gitea}/";
          startUnits = [
            "gitea.service"
            "gitea-oidc-config.service"
          ];
          stopUnits = [
            "gitea-oidc-config.service"
            "gitea.service"
          ];
          statusUnits = [ "gitea.service" ];
          health = {
            headers.Host = cfg.serviceHosts.gitea;
            url = "http://127.0.0.1:${toString cfg.ports.gitea}/";
            waitSeconds = 120;
          };
        };

        stirling-pdf = {
          name = "Stirling PDF";
          description = "PDF toolkit";
          url = "https://${cfg.serviceHosts.stirlingPdf}/";
          startUnits = [ "stirling-pdf.service" ];
          stopUnits = [ "stirling-pdf.service" ];
          statusUnits = [ "stirling-pdf.service" ];
          health = {
            headers.Host = cfg.serviceHosts.stirlingPdf;
            okStatuses = [
              200
              204
              301
              302
              303
              307
              308
              401
            ];
            url = "http://127.0.0.1:${toString cfg.ports.stirlingPdf}/";
            waitSeconds = 150;
          };
        };
      };
      description = "Allowlisted app bundles exposed by the On-Demand Apps Dashboard.";
    };

    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run the authenticated on-demand apps dashboard.";
    };

    gatewayAddress = mkOption {
      type = types.str;
      default = "10.2.20.112";
      description = "Gateway address allowed to reach the dashboard backend port.";
    };

    gatewayAddresses = mkOption {
      type = types.listOf types.str;
      default = [ cfg.onDemandLauncher.gatewayAddress ];
      description = "Gateway addresses allowed to reach the dashboard backend port.";
    };

    maintenanceLock = mkOption {
      type = types.path;
      default = "/run/on-demand-apps-dashboard/maintenance.lock";
      description = "Runtime lock file that blocks dashboard actions during host maintenance.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Allow the gateway host to reach the launcher backend port.";
    };

    port = mkOption {
      type = types.port;
      default = 8092;
      description = "LAN-facing dashboard backend port.";
    };

    publicBaseUrl = mkOption {
      type = types.str;
      default = "https://ondemand.jax22.com";
      description = "Public Authentik-protected dashboard URL used by Homepage cards.";
    };

    requireAuthHeader = mkOption {
      type = types.bool;
      default = true;
      description = "Require the Authentik forward-auth username header for HTML pages and actions.";
    };

    requireAllowedGroup = mkOption {
      type = types.bool;
      default = true;
      description = "Require at least one allowed Authentik group in the forwarded group header.";
    };
  };

  config = mkIf (cfg.enable && launcherCfg.enable) {
    users.groups.on-demand-apps-dashboard = { };
    users.users.on-demand-apps-dashboard = {
      group = "on-demand-apps-dashboard";
      isSystemUser = true;
    };

    systemd.services.gitea.wantedBy = mkForce [ ];
    systemd.services.gitea-oidc-config = mkIf cfg.gitea.oidc.enable {
      wantedBy = mkForce [ ];
    };
    systemd.services.phpfpm-firefly-iii.wantedBy = mkForce [ ];
    systemd.services.podman-affine.wantedBy = mkForce [ ];
    systemd.services.redis-affine.wantedBy = mkForce [ ];
    systemd.services.stirling-pdf.wantedBy = mkForce [ ];
    systemd.timers.firefly-iii-cron.wantedBy = mkForce [ ];

    systemd.tmpfiles.rules = [
      "d /run/on-demand-apps-dashboard 0755 root root - -"
    ];

    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        var allowedActions = ${builtins.toJSON systemctlAllowedActions};
        var allowedUnits = ${builtins.toJSON systemctlAllowedUnits};

        if (
          action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "on-demand-apps-dashboard" &&
          allowedActions.indexOf(action.lookup("verb")) >= 0 &&
          allowedUnits.indexOf(action.lookup("unit")) >= 0
        ) {
          return polkit.Result.YES;
        }
      });
    '';

    systemd.services.on-demand-apps-dashboard = {
      description = "On-demand apps dashboard";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.systemd
      ];
      serviceConfig = {
        CapabilityBoundingSet = "";
        ExecStart = "${lib.getExe pkgs.python3} ${./on-demand-launcher.py} ${launcherConfig}";
        Group = "on-demand-apps-dashboard";
        LockPersonality = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RuntimeDirectory = "on-demand-apps-dashboard";
        RuntimeDirectoryMode = "0755";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        Type = "simple";
        User = "on-demand-apps-dashboard";
        WorkingDirectory = "/run/on-demand-apps-dashboard";
      };
    };

    networking.firewall.extraCommands = mkIf launcherCfg.openFirewall (
      concatMapStringsSep "\n" (
        gatewayAddress:
        "iptables -A nixos-fw -p tcp -s ${gatewayAddress} --dport ${toString launcherCfg.port} -j nixos-fw-accept"
      ) launcherCfg.gatewayAddresses
    );
  };
}
