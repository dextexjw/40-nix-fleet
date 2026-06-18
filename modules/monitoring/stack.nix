{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  cfg = config.fleet.monitoring.stack;
  appdata = cfg.appdataRoot;
  mountUnit = "${utils.escapeSystemdPath cfg.smb.backupMount}.mount";
  serviceHosts = cfg.serviceHosts;
  statefulServices = [
    "beszel-hub.service"
    "podman-checkmate.service"
    "podman-checkmate-mongodb.service"
  ]
  ++ optional cfg.ntfy.enable "ntfy-sh.service";
  serviceRouteLines = concatStringsSep "\n" (
    concatMap
      (
        service:
        map (hostName: "        http://${hostName}") (
          [ serviceHosts.${service} ] ++ cfg.serviceHostAliases.${service}
        )
      )
      [
        "beszel"
        "checkmate"
        "ntfy"
      ]
  );
  secretPath =
    name: if cfg.secrets.enable then config.sops.secrets.${name}.path else "/run/secrets/${name}";
  resticPasswordFile = secretPath "restic-password";
  smbCredentialsFile = secretPath "smb-credentials";
  beszelOidcIssuerUrl = removeSuffix "/" cfg.beszel.oidc.issuerUrl;
  beszelOidcProviderBaseUrl = removeSuffix "/" cfg.beszel.oidc.providerBaseUrl;
  beszelOidcConfig = pkgs.writeText "beszel-oidc-config.json" (
    builtins.toJSON {
      authURL = "${beszelOidcProviderBaseUrl}/authorize/";
      clientId = cfg.beszel.oidc.clientId;
      displayName = cfg.beszel.oidc.displayName;
      extra = {
        issuers = [ "${beszelOidcIssuerUrl}/" ];
        jwksURL = "${beszelOidcIssuerUrl}/jwks/";
      };
      name = cfg.beszel.oidc.providerName;
      pkce = cfg.beszel.oidc.pkce;
      tokenURL = "${beszelOidcProviderBaseUrl}/token/";
      userInfoURL = "${beszelOidcProviderBaseUrl}/userinfo/";
    }
  );
  beszelOidcProvision = pkgs.writeShellScript "beszel-oidc-provision" ''
    set -euo pipefail

    ${lib.getExe' cfg.beszel.package "beszel-hub"} migrate up

    ${lib.getExe pkgs.python3} - <<'PY'
    import json
    import sqlite3
    from pathlib import Path

    db_path = Path("${cfg.beszel.dataDir}") / "beszel_data" / "data.db"
    secret_path = Path("${cfg.beszel.oidc.clientSecretFile}")
    with open("${beszelOidcConfig}", "r", encoding="utf-8") as config_file:
        provider = json.load(config_file)

    client_secret = secret_path.read_text(encoding="utf-8").strip()
    if not client_secret:
        raise SystemExit("Beszel OIDC client secret is empty")

    provider["clientSecret"] = client_secret

    with sqlite3.connect(db_path) as db:
        row = db.execute(
            "select options from _collections where name = ?",
            ("users",),
        ).fetchone()
        if row is None:
            raise SystemExit("Beszel users collection was not found")

        options = json.loads(row[0])
        oauth2 = options.setdefault("oauth2", {})
        oauth2["enabled"] = True
        oauth2.setdefault(
            "mappedFields",
            {
                "id": "",
                "name": "name",
                "username": "",
                "avatarURL": "avatar",
            },
        )
        providers = [
            existing
            for existing in (oauth2.get("providers") or [])
            if existing.get("name") != provider["name"]
        ]
        providers.append(provider)
        oauth2["providers"] = providers

        db.execute(
            "update _collections set options = json(?), updated = strftime('%Y-%m-%d %H:%M:%fZ') where name = ?",
            (json.dumps(options, separators=(",", ":")), "users"),
        )
    PY
  '';
  systemdMountOptions = filter (
    option:
    option != "_netdev" && option != "noauto" && option != "nofail" && !(hasPrefix "x-systemd." option)
  ) cfg.smb.mountOptions;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.monitoring.stack = {
    enable = mkEnableOption "monitoring-vm Checkmate and Beszel stack";

    appdataRoot = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Single restore-critical application data root.";
    };

    secrets.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Use sops-nix secrets from secrets/secrets.yaml.";
    };

    serviceDomain = mkOption {
      type = types.str;
      default = "h";
      description = "Legacy single internal service domain used for route hostnames.";
    };

    serviceDomains = mkOption {
      type = types.nonEmptyListOf types.str;
      default = [ cfg.serviceDomain ];
      description = "Internal service domains used for route hostnames, in canonical-first order.";
    };

    serviceHosts = mkOption {
      type = types.attrsOf types.str;
      default = {
        beszel = "beszel.${head cfg.serviceDomains}";
        checkmate = "checkmate.${head cfg.serviceDomains}";
        ntfy = "ntfy.${head cfg.serviceDomains}";
      };
      description = "Canonical internal hostnames for monitoring services.";
    };

    serviceHostAliases = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {
        beszel = tail (map (domain: "beszel.${domain}") cfg.serviceDomains);
        checkmate = tail (map (domain: "checkmate.${domain}") cfg.serviceDomains);
        ntfy = tail (map (domain: "ntfy.${domain}") cfg.serviceDomains);
      };
      description = "Alias hostnames for monitoring services.";
    };

    ports = mkOption {
      type = types.attrsOf types.port;
      default = {
        beszel = 8090;
        capture = 59232;
        checkmate = 52345;
        mongo = 27017;
        ntfy = 2586;
      };
      description = "Monitoring service ports.";
    };

    smb = {
      backupDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/backups";
        description = "SMB device for the backup share.";
      };

      backupMount = mkOption {
        type = types.path;
        default = "/mnt/backups";
        description = "Backup SMB mount point.";
      };

      mountOptions = mkOption {
        type = types.listOf types.str;
        default = [
          "vers=3.0"
          "noauto"
          "nofail"
          "x-systemd.automount"
          "x-systemd.after=network-online.target"
          "x-systemd.idle-timeout=60"
          "x-systemd.mount-timeout=30s"
          "x-systemd.requires=network-online.target"
          "_netdev"
        ];
        description = "Systemd-aware CIFS mount options.";
      };
    };

    backup = {
      repository = mkOption {
        type = types.path;
        default = "/mnt/backups/restic/appdata/monitoring-vm";
        description = "Restic repository path.";
      };

      source = mkOption {
        type = types.path;
        default = "/srv/appsdata";
        description = "Path backed up by monitoring-appdata-backup.service.";
      };

      restoreCheckTarget = mkOption {
        type = types.path;
        default = "/var/tmp/monitoring-appdata-restore-check";
        description = "Temporary target used by monitoring-appdata-restore-check.service.";
      };
    };

    checkmate = {
      image = mkOption {
        type = types.str;
        default = "ghcr.io/bluewave-labs/checkmate-backend-mono@sha256:e98de08b458389df753d506db0ea0da48ff8323845ee094d643beb377fdcdd01";
        description = "Pinned Checkmate mono OCI image.";
      };

      mongoImage = mkOption {
        type = types.str;
        default = "ghcr.io/bluewave-labs/checkmate-mongo@sha256:c9026b4150f77aae3e1d3d47b077866f906776048a538b8d609058b13a0df415";
        description = "Pinned Checkmate MongoDB OCI image.";
      };

      publicUrl = mkOption {
        type = types.str;
        default =
          let
            host = cfg.serviceHosts.checkmate;
            scheme = if hasSuffix ".h" host then "http" else "https";
          in
          "${scheme}://${host}";
        description = "Browser-facing Checkmate URL used for client API and CORS settings.";
      };
    };

    ntfy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run ntfy push notifications on monitoring-vm.";
      };

      gatewayAddress = mkOption {
        type = types.str;
        default = "10.2.20.112";
        description = "Gateway VM address allowed to reach ntfy's backend listener.";
      };

      publicUrl = mkOption {
        type = types.str;
        default =
          let
            host = cfg.serviceHosts.ntfy;
            scheme = if hasSuffix ".h" host then "http" else "https";
          in
          "${scheme}://${host}";
        description = "Public ntfy URL used as the canonical server base URL.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/ntfy";
        description = "Persistent ntfy data directory.";
      };

      upstreamBaseUrl = mkOption {
        type = types.str;
        default = "https://ntfy.sh";
        description = "Upstream ntfy server used for mobile push forwarding.";
      };
    };

    beszel = {
      package = mkOption {
        type = types.package;
        default = pkgs.beszel;
        defaultText = literalExpression "pkgs.beszel";
        description = "Beszel package used for hub service and OIDC provisioning migrations.";
      };

      dataDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/beszel-hub";
        description = "Beszel Hub data directory.";
      };

      oidc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Configure Beszel Hub's PocketBase OAuth2 provider for Authentik OIDC.";
        };

        allowUserCreation = mkOption {
          type = types.bool;
          default = true;
          description = "Allow Beszel users to be created from OAuth2 logins.";
        };

        clientId = mkOption {
          type = types.str;
          default = "beszel";
          description = "OIDC client ID registered in Authentik.";
        };

        clientSecretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing the Beszel OIDC client secret.";
        };

        disablePasswordAuth = mkOption {
          type = types.bool;
          default = false;
          description = "Disable Beszel password login after OIDC is configured.";
        };

        displayName = mkOption {
          type = types.str;
          default = "Authentik";
          description = "OAuth login button label.";
        };

        issuerUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/beszel";
          description = "Authentik per-application OAuth2 issuer URL without trailing slash.";
        };

        providerBaseUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o";
          description = "Authentik OAuth2 endpoint base URL used for authorize, token, and userinfo.";
        };

        pkce = mkOption {
          type = types.bool;
          default = true;
          description = "Enable PKCE for Beszel's OIDC provider config.";
        };

        providerName = mkOption {
          type = types.enum [
            "oidc"
            "oidc2"
            "oidc3"
          ];
          default = "oidc";
          description = "PocketBase OIDC provider slot used by Beszel.";
        };

      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.beszel.oidc.enable || cfg.beszel.oidc.clientSecretFile != null;
        message = "fleet.monitoring.stack.beszel.oidc.clientSecretFile must be set when Beszel OIDC is enabled.";
      }
    ];

    boot.supportedFilesystems.cifs = true;
    environment.systemPackages = [ pkgs.restic ];

    users.groups.monitoring = { };
    users.groups.beszel-hub = { };
    users.users.beszel-hub = {
      isSystemUser = true;
      group = "beszel-hub";
      home = "${appdata}/beszel-hub";
    };

    systemd.tmpfiles.rules = [
      "d '${appdata}' 0755 root root - -"
      "d '${cfg.beszel.dataDir}' 0750 beszel-hub beszel-hub - -"
      "z '${cfg.beszel.dataDir}' 0750 beszel-hub beszel-hub - -"
      "d '${appdata}/checkmate' 0750 root monitoring - -"
      "d '${appdata}/checkmate/mongo' 0750 root monitoring - -"
      "d '${appdata}/checkmate/uploads' 0750 root monitoring - -"
    ]
    ++ optionals cfg.ntfy.enable [
      "d '${cfg.ntfy.stateDir}' 0750 ntfy-sh ntfy-sh - -"
      "z '${cfg.ntfy.stateDir}' 0750 ntfy-sh ntfy-sh - -"
      "d '${cfg.ntfy.stateDir}/attachments' 0750 ntfy-sh ntfy-sh - -"
      "z '${cfg.ntfy.stateDir}/attachments' 0750 ntfy-sh ntfy-sh - -"
    ];

    systemd.automounts = [
      {
        where = toString cfg.smb.backupMount;
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "60s";
      }
    ];

    systemd.mounts = [
      {
        description = "Backup SMB share";
        what = cfg.smb.backupDevice;
        where = toString cfg.smb.backupMount;
        type = "cifs";
        options = concatStringsSep "," (
          systemdMountOptions
          ++ [
            "credentials=${smbCredentialsFile}"
            "dir_mode=0750"
            "file_mode=0640"
            "forcegid"
            "gid=monitoring"
          ]
        );
        after = [ "network-online.target" ];
        before = [ "umount.target" ];
        conflicts = [ "umount.target" ];
        requires = [ "network-online.target" ];
        unitConfig.DefaultDependencies = false;
        mountConfig.TimeoutSec = "30s";
      }
    ];

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.checkmate-mongodb = {
      image = cfg.checkmate.mongoImage;
      pull = "missing";
      cmd = [
        "mongod"
        "--quiet"
        "--bind_ip"
        "127.0.0.1"
      ];
      extraOptions = [
        "--network=host"
        "--security-opt=no-new-privileges"
      ];
      volumes = [
        "${appdata}/checkmate/mongo:/data/db"
      ];
    };

    virtualisation.oci-containers.containers.checkmate = {
      image = cfg.checkmate.image;
      pull = "missing";
      dependsOn = [ "checkmate-mongodb" ];
      environment = {
        CLIENT_HOST = cfg.checkmate.publicUrl;
        DB_CONNECTION_STRING = "mongodb://127.0.0.1:${toString cfg.ports.mongo}/uptime_db";
        UPTIME_ALLOWED_ORIGINS = cfg.checkmate.publicUrl;
        UPTIME_APP_API_BASE_URL = "${cfg.checkmate.publicUrl}/api/v1";
        UPTIME_APP_CLIENT_HOST = cfg.checkmate.publicUrl;
        UPTIME_APP_PUBLIC_ASSETS_URL = "${cfg.checkmate.publicUrl}/uploads";
        UPTIME_APP_UPLOAD_DIR = "/app/uploads";
      };
      environmentFiles = [ (secretPath "checkmate-environment") ];
      extraOptions = [
        "--cap-drop=ALL"
        "--network=host"
        "--security-opt=no-new-privileges"
      ];
      volumes = [
        "${appdata}/checkmate/uploads:/app/uploads"
      ];
    };

    services.beszel.hub = {
      dataDir = cfg.beszel.dataDir;
      enable = true;
      host = "0.0.0.0";
      port = cfg.ports.beszel;
      environment = mkIf cfg.beszel.oidc.enable (
        {
          USER_CREATION = if cfg.beszel.oidc.allowUserCreation then "true" else "false";
        }
        // optionalAttrs cfg.beszel.oidc.disablePasswordAuth {
          DISABLE_PASSWORD_AUTH = "true";
        }
      );
    };

    systemd.services.beszel-hub-oidc-config = mkIf cfg.beszel.oidc.enable {
      description = "Configure Beszel Hub OAuth2/OIDC provider";
      after = [ "systemd-tmpfiles-setup.service" ];
      before = [ "beszel-hub.service" ];
      requiredBy = [ "beszel-hub.service" ];
      serviceConfig = {
        ExecStart = beszelOidcProvision;
        Group = "beszel-hub";
        Type = "oneshot";
        User = "beszel-hub";
        WorkingDirectory = cfg.beszel.dataDir;
      };
    };

    systemd.services.beszel-hub.serviceConfig = {
      DynamicUser = mkForce false;
      Group = "beszel-hub";
      StateDirectory = mkForce "";
      User = "beszel-hub";
    };

    systemd.services.podman-checkmate-mongodb = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.services.podman-checkmate = {
      after = [
        "network-online.target"
        "podman-checkmate-mongodb.service"
      ];
      requires = [ "podman-checkmate-mongodb.service" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.services.monitoring-appdata-backup = {
      description = "Back up monitoring-vm /srv/appsdata with restic";
      after = [
        "network-online.target"
        mountUnit
      ];
      wants = [ "network-online.target" ];
      requires = [ mountUnit ];
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.systemd
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-monitoring-appdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run backup'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-monitoring-appdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup"
          exit 1
        fi

        services=(${concatStringsSep " " (map escapeShellArg statefulServices)})
        active_services=()
        for service in "''${services[@]}"; do
          if systemctl is-active --quiet "$service"; then
            active_services+=("$service")
          fi
        done

        restart_services() {
          for ((i=''${#active_services[@]} - 1; i >= 0; i--)); do
            systemctl start "''${active_services[$i]}" || true
          done
        }
        trap restart_services EXIT

        systemctl stop "''${services[@]}" || true

        mkdir -p "$RESTIC_REPOSITORY"
        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          restic init
        else
          restic snapshots \
            --host monitoring-vm \
            --path '${cfg.backup.source}' \
            --tag appsdata \
            --latest 1 \
            --retry-lock 30m \
            >/dev/null
        fi

        restic backup '${cfg.backup.source}' \
          --host monitoring-vm \
          --one-file-system \
          --exclude-caches \
          --retry-lock 30m \
          --tag appsdata
        restic forget \
          --host monitoring-vm \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --path '${cfg.backup.source}' \
          --prune \
          --retry-lock 30m \
          --tag appsdata

        trap - EXIT
        restart_services
      '';
    };

    systemd.services.monitoring-appdata-restore-check = {
      description = "Verify monitoring-vm /srv/appsdata can be restored from restic";
      after = [
        "network-online.target"
        mountUnit
      ];
      wants = [ "network-online.target" ];
      requires = [ mountUnit ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-monitoring-appdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run restore check'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-monitoring-appdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run restore check"
          exit 1
        fi

        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          echo "$RESTIC_REPOSITORY is not an initialized restic repository"
          exit 1
        fi

        restore_parent='${cfg.backup.restoreCheckTarget}'
        case "$restore_parent" in
          /tmp/*|/var/tmp/*) ;;
          *)
            echo "restore check target must be under /tmp or /var/tmp: $restore_parent"
            exit 1
            ;;
        esac

        rm -rf -- "$restore_parent"
        install -d -m 0700 -o root -g root "$restore_parent"
        restore_root="$(mktemp -d "$restore_parent/run.XXXXXX")"
        cleanup() {
          rm -rf -- "$restore_root"
        }
        trap cleanup EXIT

        restic check --retry-lock 30m
        restic restore latest \
          --host monitoring-vm \
          --path '${cfg.backup.source}' \
          --tag appsdata \
          --target "$restore_root" \
          --verify \
          --retry-lock 30m

        restored_source="$restore_root${cfg.backup.source}"
        if [ ! -d "$restored_source" ]; then
          echo "restore completed but $restored_source is missing"
          exit 1
        fi

        first_entry="$(find "$restored_source" -mindepth 1 -maxdepth 1 -print -quit)"
        if [ -z "$first_entry" ]; then
          echo "restore completed but $restored_source is empty"
          exit 1
        fi
      '';
    };

    systemd.timers.monitoring-appdata-backup = {
      description = "Daily monitoring-vm /srv/appsdata restic backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        Unit = "monitoring-appdata-backup.service";
      };
    };

    networking.firewall.allowedTCPPorts = [
      cfg.ports.beszel
      cfg.ports.checkmate
    ];
    networking.firewall.extraCommands = optionalString cfg.ntfy.enable ''
      iptables -A nixos-fw -p tcp -s ${cfg.ntfy.gatewayAddress} --dport ${toString cfg.ports.ntfy} -j nixos-fw-accept
    '';

    environment.etc."fleet/monitoring-vm.md".text = ''
            monitoring-vm service model
            ===========================

            monitoring-vm runs Checkmate, Beszel Hub, ntfy, Beszel Agent,
            Checkmate Capture, and Restic appdata backups.

            Persistent state root:
              ${appdata}

            Backup repository:
              ${cfg.backup.repository}

            Password file:
              ${resticPasswordFile}

            Internal routes through gateway-vm:
      ${serviceRouteLines}

            Direct LAN ports:
              Checkmate: ${toString cfg.ports.checkmate}
              Beszel: ${toString cfg.ports.beszel}
              ntfy: ${toString cfg.ports.ntfy} (gateway-vm only)
              Checkmate Capture: ${toString cfg.ports.capture}
              Beszel Agent: 45876

            Checkmate provisioning:
              Unit: checkmate-provisioning.service
              Targets: /etc/fleet/checkmate-targets.json
              Last summary: /var/lib/checkmate-provisioning/last-summary.json
              Managed identity: fleet-declared plus fleet-service:<id> or fleet-host:<host>
              Expected managed monitors: 41
              Stale managed monitors are paused, not deleted.

            Beszel SSO:
              Unit: beszel-hub-oidc-config.service
              Provider: Authentik OIDC, client ID ${cfg.beszel.oidc.clientId}
              Redirect URI: https://beszel.jax22.com/api/oauth2-redirect
              Password login stays enabled unless fleet.monitoring.stack.beszel.oidc.disablePasswordAuth is true.

            Backup validation:
              mount ${cfg.smb.backupMount}
              systemctl start monitoring-appdata-backup.service
              systemctl start monitoring-appdata-restore-check.service
              systemctl status monitoring-appdata-backup.service monitoring-appdata-restore-check.service

            Restore outline:
              1. Deploy monitoring-vm once to create users, secrets, mounts, and units.
              2. Stop monitoring-appdata-backup.timer, beszel-hub.service, podman-checkmate.service, podman-checkmate-mongodb.service, and ntfy-sh.service.
              3. Mount ${cfg.smb.backupMount}.
              4. Choose a monitoring-vm/appsdata snapshot ID.
              5. Restore the snapshot to / with restic --verify.
              6. Run systemd-tmpfiles --create.
              7. Restart Beszel Hub, Checkmate MongoDB, Checkmate, ntfy, and the backup timer.

            ntfy:
              Public URL: ${cfg.ntfy.publicUrl}
              State: ${cfg.ntfy.stateDir}
              Health: http://127.0.0.1:${toString cfg.ports.ntfy}/v1/health
              Mobile push forwarding uses upstream-base-url ${cfg.ntfy.upstreamBaseUrl}.
    '';
  };
}
