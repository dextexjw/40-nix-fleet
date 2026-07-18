{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  testbedLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg;
  karakeepCfg = cfg.karakeep;
in
{
  config = mkIf (cfg.enable && karakeepCfg.enable) {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "karakeep-environment" config.sops.templates;
        message = "karakeep-environment must be declared as a SOPS template when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "karakeep-oidc-client-secret" config.sops.secrets;
        message = "karakeep-oidc-client-secret must be declared as a SOPS secret when testbed secrets are enabled.";
      }
    ];

    virtualisation.oci-containers.backend = "podman";
    systemd.user.sockets.podman.wantedBy = mkForce [ ];

    virtualisation.oci-containers.containers = {
      karakeep = {
        image = karakeepCfg.image;
        pull = "missing";
        environment = {
          BROWSER_WEB_URL = "http://127.0.0.1:${toString cfg.ports.karakeepBrowser}";
          DATA_DIR = "/data";
          DB_WAL_MODE = "true";
          LOG_LEVEL = "notice";
          MEILI_ADDR = "http://127.0.0.1:${toString cfg.ports.karakeepMeilisearch}";
          NEXTAUTH_URL = karakeepCfg.externalUrl;
          OAUTH_CLIENT_ID = "karakeep";
          OAUTH_PROVIDER_NAME = "Authentik";
          OAUTH_SCOPE = "openid email profile";
          OAUTH_WELLKNOWN_URL = "https://auth.jax22.com/application/o/karakeep/.well-known/openid-configuration";
          PORT = toString cfg.ports.karakeep;
        };
        environmentFiles = [ (toString karakeepCfg.environmentFile) ];
        volumes = [ "${karakeepCfg.stateDir}/data:/data" ];
        extraOptions = [
          "--cap-drop=ALL"
          "--network=host"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
        ];
      };

      karakeep-browser = {
        image = karakeepCfg.browserImage;
        pull = "missing";
        cmd = [
          "--no-sandbox"
          "--disable-gpu"
          "--disable-dev-shm-usage"
          "--remote-debugging-address=127.0.0.1"
          "--remote-debugging-port=${toString cfg.ports.karakeepBrowser}"
          "--hide-scrollbars"
          "--disable-blink-features=AutomationControlled"
          "--window-size=1440,900"
        ];
        extraOptions = [
          "--cap-drop=ALL"
          "--network=host"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp:rw,noexec,nosuid,size=512m"
        ];
      };

      karakeep-meilisearch = {
        image = karakeepCfg.meilisearchImage;
        pull = "missing";
        environment = {
          MEILI_ENV = "production";
          MEILI_HTTP_ADDR = "127.0.0.1:${toString cfg.ports.karakeepMeilisearch}";
          MEILI_NO_ANALYTICS = "true";
        };
        environmentFiles = [ (toString karakeepCfg.environmentFile) ];
        volumes = [ "${karakeepCfg.stateDir}/meilisearch:/meili_data" ];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
        ];
      };
    };

    systemd.services = {
      podman-karakeep-browser = {
        after = [
          "network-online.target"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [ "systemd-tmpfiles-setup.service" ];
        wants = [ "network-online.target" ];
        serviceConfig.RestartSec = "30s";
      };
      podman-karakeep-meilisearch = {
        after = [
          "network-online.target"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [ "systemd-tmpfiles-setup.service" ];
        wants = [ "network-online.target" ];
        serviceConfig.RestartSec = "30s";
      };
      podman-karakeep = {
        after = [
          "network-online.target"
          "podman-karakeep-browser.service"
          "podman-karakeep-meilisearch.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "podman-karakeep-browser.service"
          "podman-karakeep-meilisearch.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };
    };
  };
}
