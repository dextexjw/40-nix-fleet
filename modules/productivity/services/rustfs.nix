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
  inherit (productivityLib)
    cfg
    appdata
    secretPath
    serviceHosts
    ;
  oidcCfg = cfg.rustfs.oidc;
  rustfsOidcProviderSuffix = "_${oidcCfg.providerId}";
  rustfsOidcPolicy = pkgs.writeText "rustfs-console-admin-policy.json" (
    builtins.toJSON {
      Version = "2012-10-17";
      Statement = [
        {
          Effect = "Allow";
          Action = [
            "admin:*"
          ];
          Resource = [
            "arn:aws:s3:::*"
            "arn:aws:s3:::*/*"
          ];
        }
        {
          Effect = "Allow";
          Action = [ "s3:*" ];
          Resource = [
            "arn:aws:s3:::*"
            "arn:aws:s3:::*/*"
          ];
        }
      ];
    }
  );
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.minio-client ];

    virtualisation.oci-containers.containers.rustfs = {
      image = "docker.io/rustfs/rustfs@sha256:029bab58b7cfca8b3b3483d49ac073075f555d7cc50abdd706d7df74bf6ec432";
      pull = "missing";

      environment = {
        RUSTFS_ADDRESS = "0.0.0.0:${toString cfg.ports.rustfsApi}";
        RUSTFS_CONSOLE_ADDRESS = "0.0.0.0:${toString cfg.ports.rustfsConsole}";
        RUSTFS_CONSOLE_ENABLE = "true";
        RUSTFS_SERVER_DOMAINS = serviceHosts.rustfs;
        RUSTFS_VOLUMES = "/data";
      }
      // optionalAttrs oidcCfg.enable {
        "RUSTFS_IDENTITY_OPENID_ENABLE${rustfsOidcProviderSuffix}" = "on";
        "RUSTFS_IDENTITY_OPENID_CONFIG_URL${rustfsOidcProviderSuffix}" = oidcCfg.configUrl;
        "RUSTFS_IDENTITY_OPENID_CLIENT_ID${rustfsOidcProviderSuffix}" = oidcCfg.clientId;
        "RUSTFS_IDENTITY_OPENID_DISPLAY_NAME${rustfsOidcProviderSuffix}" = oidcCfg.displayName;
        "RUSTFS_IDENTITY_OPENID_REDIRECT_URI${rustfsOidcProviderSuffix}" = oidcCfg.redirectUri;
        "RUSTFS_IDENTITY_OPENID_REDIRECT_URI_DYNAMIC${rustfsOidcProviderSuffix}" = "off";
        "RUSTFS_IDENTITY_OPENID_ROLE_POLICY${rustfsOidcProviderSuffix}" = oidcCfg.rolePolicy;
        "RUSTFS_IDENTITY_OPENID_SCOPES${rustfsOidcProviderSuffix}" = concatStringsSep "," oidcCfg.scopes;
      };
      environmentFiles = [
        (secretPath "rustfs-environment")
      ]
      ++ optional oidcCfg.enable oidcCfg.environmentFile;

      extraOptions = [
        "--cap-drop=ALL"
        "--health-cmd=sh -c 'curl -f http://127.0.0.1:${toString cfg.ports.rustfsApi}/health && curl -f http://127.0.0.1:${toString cfg.ports.rustfsConsole}/rustfs/console/health'"
        "--health-interval=30s"
        "--health-retries=3"
        "--health-start-period=40s"
        "--health-timeout=10s"
        "--security-opt=no-new-privileges"
      ];

      podman.sdnotify = "healthy";

      ports = [
        "0.0.0.0:${toString cfg.ports.rustfsApi}:${toString cfg.ports.rustfsApi}/tcp"
        "0.0.0.0:${toString cfg.ports.rustfsConsole}:${toString cfg.ports.rustfsConsole}/tcp"
      ];

      volumes = [
        "${appdata}/rustfs/data:/data"
      ];
    };

    systemd.services.podman-rustfs = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.services.rustfs-oidc-policy = mkIf oidcCfg.enable {
      description = "Ensure RustFS OIDC console IAM policy";
      after = [ "podman-rustfs.service" ];
      requires = [ "podman-rustfs.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.diffutils
        pkgs.glibc.bin
        pkgs.jq
        pkgs.minio-client
      ];
      script = ''
        set -euo pipefail

        for attempt in $(seq 1 120); do
          if curl -fsS --max-time 5 "http://127.0.0.1:${toString cfg.ports.rustfsApi}/health" >/dev/null; then
            break
          fi

          if [ "$attempt" = 120 ]; then
            echo "RustFS API did not become healthy" >&2
            exit 1
          fi

          sleep 1
        done

        set -a
        . "${secretPath "rustfs-environment"}"
        set +a

        if [ -z "''${RUSTFS_ACCESS_KEY:-}" ] || [ -z "''${RUSTFS_SECRET_KEY:-}" ]; then
          echo "rustfs-environment must define RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY" >&2
          exit 1
        fi

        export MC_CONFIG_DIR="$(mktemp -d)"
        export HOME="$MC_CONFIG_DIR"
        trap 'rm -rf "$MC_CONFIG_DIR"' EXIT

        mc alias set rustfs "http://127.0.0.1:${toString cfg.ports.rustfsApi}" "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" --api S3v4 >/dev/null

        existing_policy="$(mktemp)"
        expected_policy="$(mktemp)"
        canonical_policy='
          def norm_statement:
            .Action |= sort |
            .Resource |= sort |
            del(.Condition, .Sid);
          .policy // . |
          del(.ID) |
          .Statement |= (map(norm_statement) | sort_by((.Action | join(",")), (.Resource | join(",")), .Effect))
        '
        jq -S "$canonical_policy" "${rustfsOidcPolicy}" > "$expected_policy"

        if mc admin policy info rustfs "${oidcCfg.rolePolicy}" --policy-file "$existing_policy" >/dev/null 2>&1; then
          if ! jq -S "$canonical_policy" "$existing_policy" | cmp -s - "$expected_policy"; then
            echo "RustFS policy ${oidcCfg.rolePolicy} exists but does not match the declarative policy" >&2
            exit 1
          fi
        else
          mc admin policy create rustfs "${oidcCfg.rolePolicy}" "${rustfsOidcPolicy}" >/dev/null
        fi

        mc admin policy info rustfs "${oidcCfg.rolePolicy}" >/dev/null
      '';
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
    };
  };
}
