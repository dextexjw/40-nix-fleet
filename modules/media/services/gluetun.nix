{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  mediaLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (mediaLib)
    cfg
    gluetunCfg
    gluetunControlAuthConfigDir
    gluetunControlAuthConfigFile
    gluetunControlWebUiEnvFile
    gluetunInputPorts
    ;
in
{
  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers = {
      media-gluetun = {
        image = gluetunCfg.image;
        pull = "missing";

        capabilities.NET_ADMIN = true;
        devices = [
          "/dev/net/tun:/dev/net/tun"
        ];

        environment = {
          FIREWALL_OUTBOUND_SUBNETS = "10.2.20.0/24";
          HTTP_CONTROL_SERVER_ADDRESS = ":${toString gluetunCfg.controlServer.port}";
          HTTP_CONTROL_SERVER_AUTH_CONFIG_FILEPATH = "/run/media-gluetun-control-server/config.toml";
          HTTPPROXY = "off";
          OPENVPN_PASSWORD_SECRETFILE = "/run/secrets/openvpn_password";
          OPENVPN_USER_SECRETFILE = "/run/secrets/openvpn_user";
          TZ = config.time.timeZone;
          VPN_PORT_FORWARDING = if gluetunCfg.vpnPortForwarding then "on" else "off";
          VPN_SERVICE_PROVIDER = gluetunCfg.provider;
          VPN_TYPE = gluetunCfg.vpnType;
        }
        // optionalAttrs (gluetunInputPorts != [ ]) {
          FIREWALL_INPUT_PORTS = concatMapStringsSep "," toString gluetunInputPorts;
        };

        ports =
          optionals gluetunCfg.qbittorrentWebUi.enable [
            "${gluetunCfg.bindAddress}:${toString cfg.ports.qbittorrent}:${toString cfg.ports.qbittorrent}/tcp"
          ]
          ++ [
            "${gluetunCfg.bindAddress}:${toString cfg.ports.sabnzbd}:${toString cfg.ports.sabnzbd}/tcp"
          ]
          ++ optionals gluetunCfg.webUi.enable [
            "${gluetunCfg.bindAddress}:${toString gluetunCfg.webUi.port}:${toString gluetunCfg.webUi.port}/tcp"
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
          "${gluetunCfg.stateDir}:/gluetun"
          "${gluetunCfg.openvpnUsernameFile}:/run/secrets/openvpn_user:ro"
          "${gluetunCfg.openvpnPasswordFile}:/run/secrets/openvpn_password:ro"
          "${gluetunControlAuthConfigFile}:/run/media-gluetun-control-server/config.toml:ro"
        ];
      };

      media-gluetun-webui = mkIf gluetunCfg.webUi.enable {
        image = gluetunCfg.webUi.image;
        pull = "missing";

        dependsOn = [ "media-gluetun" ];

        environment = {
          GLUETUN_CONTROL_URL = "http://127.0.0.1:${toString gluetunCfg.controlServer.port}";
          GLUETUN_NAME = gluetunCfg.webUi.name;
          PORT = toString gluetunCfg.webUi.port;
          TRUST_PROXY = if gluetunCfg.webUi.trustProxy then "true" else "false";
        };
        environmentFiles = [ gluetunControlWebUiEnvFile ];

        extraOptions = [
          "--cap-drop=ALL"
          "--network=container:media-gluetun"
          "--read-only"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp"
        ];
      };
    };

    systemd.services = {
      media-gluetun-control-auth-config = {
        description = "Generate MediaVM Gluetun control server authentication config";
        before = [ "podman-media-gluetun.service" ];
        path = [
          pkgs.coreutils
        ];
        serviceConfig = {
          RemainAfterExit = true;
          Type = "oneshot";
        };
        script = ''
                set -euo pipefail

                install -d -m 0700 -o root -g root '${gluetunControlAuthConfigDir}'

                api_key="$(tr -d '\r\n' < '${gluetunCfg.controlServer.apiKeyFile}')"
                if [ -z "$api_key" ]; then
                  echo '${gluetunCfg.controlServer.apiKeyFile} is empty; refusing to generate MediaVM Gluetun control auth config' >&2
                  exit 1
                fi

                tmp="$(mktemp '${gluetunControlAuthConfigDir}/config.toml.XXXXXX')"
                chmod 0400 "$tmp"
                cat >"$tmp" <<EOF
          [[roles]]
          name = "media-gluetun-webui"
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

                install -m 0400 -o root -g root "$tmp" '${gluetunControlAuthConfigFile}'
                rm -f "$tmp"

                env_tmp="$(mktemp '${gluetunControlAuthConfigDir}/webui.env.XXXXXX')"
                chmod 0400 "$env_tmp"
                printf 'GLUETUN_API_KEY=%s\n' "$api_key" >"$env_tmp"
                install -m 0400 -o root -g root "$env_tmp" '${gluetunControlWebUiEnvFile}'
                rm -f "$env_tmp"
        '';
      };

      podman-media-gluetun = {
        after = [
          "media-gluetun-control-auth-config.service"
          "network-online.target"
        ];
        requires = [ "media-gluetun-control-auth-config.service" ];
        wants = [ "network-online.target" ];
        serviceConfig.RestartSec = "30s";
      };

      podman-media-gluetun-webui = mkIf gluetunCfg.webUi.enable {
        after = [
          "media-gluetun-control-auth-config.service"
          "podman-media-gluetun.service"
        ];
        bindsTo = [ "podman-media-gluetun.service" ];
        partOf = [ "podman-media-gluetun.service" ];
        requires = [
          "media-gluetun-control-auth-config.service"
          "podman-media-gluetun.service"
        ];
        serviceConfig.RestartSec = "30s";
      };
    };
  };
}
