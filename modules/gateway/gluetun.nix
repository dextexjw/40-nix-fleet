{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.gluetun;
  controlAuthConfigDir = "/run/gluetun-control-server";
  controlAuthConfigFile = "${controlAuthConfigDir}/config.toml";
  controlWebUiEnvFile = "${controlAuthConfigDir}/webui.env";
  inputPorts =
    optional cfg.httpProxy.enable cfg.httpProxy.port ++ optional cfg.webUi.enable cfg.webUi.port;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.gluetun = {
    enable = mkEnableOption "Gluetun VPN gateway container";

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address used for exposed Gluetun proxy listeners.";
      example = "10.2.20.112";
    };

    httpProxy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Expose Gluetun's unauthenticated HTTP proxy.";
      };

      port = mkOption {
        type = types.port;
        default = 8888;
        description = "Host and container port for Gluetun's HTTP proxy.";
      };
    };

    controlServer = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Gluetun's authenticated HTTP control server for local integrations.";
      };

      apiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime secret file containing the Gluetun control server API key.";
      };

      port = mkOption {
        type = types.port;
        default = 8000;
        description = "Container-only Gluetun HTTP control server port.";
      };
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/qdm12/gluetun@sha256:2f33c71e5e164fcd51a962cb950134df25155593edf0c3e1201f888d027049b4";
      description = "Pinned Gluetun OCI image reference.";
    };

    openvpnPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Runtime secret file containing the PIA OpenVPN password.";
    };

    openvpnUsernameFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Runtime secret file containing the PIA OpenVPN username.";
    };

    provider = mkOption {
      type = types.str;
      default = "private internet access";
      description = "Gluetun VPN service provider name.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/srv/appsdata/gluetun";
      description = "Persistent Gluetun state directory.";
    };

    vpnPortForwarding = mkOption {
      type = types.bool;
      default = false;
      description = "Enable PIA VPN port forwarding.";
    };

    vpnType = mkOption {
      type = types.enum [ "openvpn" ];
      default = "openvpn";
      description = "Gluetun VPN protocol.";
    };

    webUi = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Run the Gluetun WebUI sidecar container.";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address used for the Gluetun WebUI listener.";
      };

      image = mkOption {
        type = types.str;
        default = "docker.io/scuzza/gluetun-webui@sha256:7f38c188ada9b21b585dcb28175c3d74e64c12d959bd979b7f106e4240f6c807";
        description = "Pinned Gluetun WebUI OCI image reference.";
      };

      name = mkOption {
        type = types.str;
        default = "Gateway Gluetun";
        description = "Display name for the Gateway Gluetun instance.";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Open the host firewall for the Gluetun WebUI port.";
      };

      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Host and container port for the Gluetun WebUI.";
      };

      trustProxy = mkOption {
        type = types.bool;
        default = false;
        description = "Allow Gluetun WebUI to trust reverse proxy forwarding headers.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.openvpnUsernameFile != null;
        message = "fleet.gateway.gluetun.openvpnUsernameFile must be set.";
      }
      {
        assertion = cfg.openvpnPasswordFile != null;
        message = "fleet.gateway.gluetun.openvpnPasswordFile must be set.";
      }
      {
        assertion = !cfg.webUi.enable || cfg.controlServer.enable;
        message = "fleet.gateway.gluetun.controlServer.enable must be true when fleet.gateway.gluetun.webUi.enable is true.";
      }
      {
        assertion = !cfg.controlServer.enable || cfg.controlServer.apiKeyFile != null;
        message = "fleet.gateway.gluetun.controlServer.apiKeyFile must be set when the Gluetun control server is enabled.";
      }
    ];

    boot.kernelModules = [ "tun" ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root - -"
    ];

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.gluetun = {
      image = cfg.image;
      pull = "missing";

      capabilities.NET_ADMIN = true;
      devices = [
        "/dev/net/tun:/dev/net/tun"
      ];

      environment = {
        FIREWALL_OUTBOUND_SUBNETS = "10.2.20.0/24";
        HTTPPROXY = if cfg.httpProxy.enable then "on" else "off";
        HTTPPROXY_LISTENING_ADDRESS = ":${toString cfg.httpProxy.port}";
        OPENVPN_PASSWORD_SECRETFILE = "/run/secrets/openvpn_password";
        OPENVPN_USER_SECRETFILE = "/run/secrets/openvpn_user";
        VPN_PORT_FORWARDING = if cfg.vpnPortForwarding then "on" else "off";
        VPN_SERVICE_PROVIDER = cfg.provider;
        VPN_TYPE = cfg.vpnType;
      }
      // optionalAttrs (inputPorts != [ ]) {
        FIREWALL_INPUT_PORTS = concatMapStringsSep "," toString inputPorts;
      }
      // optionalAttrs cfg.controlServer.enable {
        HTTP_CONTROL_SERVER_ADDRESS = ":${toString cfg.controlServer.port}";
        HTTP_CONTROL_SERVER_AUTH_CONFIG_FILEPATH = "/run/gluetun-control-server/config.toml";
      };

      ports =
        optionals cfg.httpProxy.enable [
          "${cfg.bindAddress}:${toString cfg.httpProxy.port}:${toString cfg.httpProxy.port}/tcp"
        ]
        ++ optionals cfg.webUi.enable [
          "${cfg.webUi.bindAddress}:${toString cfg.webUi.port}:${toString cfg.webUi.port}/tcp"
        ];

      podman.sdnotify = "healthy";

      extraOptions = [
        "--health-cmd=/gluetun-entrypoint healthcheck"
        "--health-interval=5s"
        "--health-retries=1"
        "--health-start-period=10s"
        "--health-timeout=5s"
      ];

      volumes = [
        "${cfg.stateDir}:/gluetun"
        "${cfg.openvpnUsernameFile}:/run/secrets/openvpn_user:ro"
        "${cfg.openvpnPasswordFile}:/run/secrets/openvpn_password:ro"
      ]
      ++ optionals cfg.controlServer.enable [
        "${controlAuthConfigFile}:/run/gluetun-control-server/config.toml:ro"
      ];
    };

    virtualisation.oci-containers.containers.gluetun-webui = mkIf cfg.webUi.enable {
      image = cfg.webUi.image;
      pull = "missing";

      dependsOn = [ "gluetun" ];

      environment = {
        GLUETUN_CONTROL_URL = "http://127.0.0.1:${toString cfg.controlServer.port}";
        GLUETUN_NAME = cfg.webUi.name;
        PORT = toString cfg.webUi.port;
        TRUST_PROXY = if cfg.webUi.trustProxy then "true" else "false";
      };
      environmentFiles = [ controlWebUiEnvFile ];

      extraOptions = [
        "--cap-drop=ALL"
        "--network=container:gluetun"
        "--read-only"
        "--security-opt=no-new-privileges"
        "--tmpfs=/tmp"
      ];
    };

    networking.firewall.allowedTCPPorts =
      optional cfg.httpProxy.enable cfg.httpProxy.port
      ++ optional (cfg.webUi.enable && cfg.webUi.openFirewall) cfg.webUi.port;

    systemd.services.gluetun-control-auth-config = mkIf cfg.controlServer.enable {
      description = "Generate Gluetun control server authentication config";
      after = [ "sops-install-secrets.service" ];
      before = [ "podman-gluetun.service" ];
      path = [
        pkgs.coreutils
      ];
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      script = ''
                set -euo pipefail

                install -d -m 0700 -o root -g root '${controlAuthConfigDir}'

                api_key="$(tr -d '\r\n' < '${cfg.controlServer.apiKeyFile}')"
                if [ -z "$api_key" ]; then
                  echo '${cfg.controlServer.apiKeyFile} is empty; refusing to generate Gluetun control auth config' >&2
                  exit 1
                fi

                tmp="$(mktemp '${controlAuthConfigDir}/config.toml.XXXXXX')"
                chmod 0400 "$tmp"
                cat >"$tmp" <<EOF
        [[roles]]
        name = "gluetun-webui"
        routes = [
          "GET /v1/dns/status",
          "GET /v1/portforward",
          "GET /v1/publicip/ip",
          "GET /v1/vpn/settings",
          "GET /v1/vpn/status",
          "PUT /v1/vpn/status"
        ]
        auth = "apikey"
        apikey = "$api_key"
        EOF

                install -m 0400 -o root -g root "$tmp" '${controlAuthConfigFile}'
                rm -f "$tmp"

                env_tmp="$(mktemp '${controlAuthConfigDir}/webui.env.XXXXXX')"
                chmod 0400 "$env_tmp"
                printf 'GLUETUN_API_KEY=%s\n' "$api_key" >"$env_tmp"
                install -m 0400 -o root -g root "$env_tmp" '${controlWebUiEnvFile}'
                rm -f "$env_tmp"
      '';
    };

    systemd.services.podman-gluetun = {
      after = [
        "gluetun-control-auth-config.service"
        "network-online.target"
        "sops-install-secrets.service"
      ];
      requires = mkIf cfg.controlServer.enable [ "gluetun-control-auth-config.service" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.services.podman-gluetun-webui = mkIf cfg.webUi.enable {
      after = [
        "gluetun-control-auth-config.service"
        "podman-gluetun.service"
        "sops-install-secrets.service"
      ];
      partOf = [ "podman-gluetun.service" ];
      requires = [
        "gluetun-control-auth-config.service"
        "podman-gluetun.service"
      ];
      serviceConfig.RestartSec = "30s";
    };
  };
}
