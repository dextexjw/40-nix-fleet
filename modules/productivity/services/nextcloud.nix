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
    serviceHostAliases
    serviceHosts
    ;
  oidcCfg = cfg.nextcloud.oidc;
  adminUsernameFile = secretPath "nextcloud-admin-username";
  adminPasswordFile = secretPath "nextcloud-admin-password";
  oidcClientSecretFile =
    if oidcCfg.clientSecretFile == null then
      "/run/secrets/UNSET"
    else
      toString oidcCfg.clientSecretFile;
  nextcloudAdminProvision = pkgs.writeShellScript "nextcloud-admin-user" ''
    set -euo pipefail

    IFS= read -r admin_user < ${adminUsernameFile} || [ -n "$admin_user" ]
    test -n "$admin_user"

    export OC_PASS="$(<${adminPasswordFile})"
    test -n "$OC_PASS"

    for attempt in $(seq 1 60); do
      if nextcloud-occ status >/dev/null 2>&1; then
        break
      fi
      if [ "$attempt" -eq 60 ]; then
        echo "Nextcloud did not become ready for admin user provisioning" >&2
        exit 1
      fi
      sleep 2
    done

    if nextcloud-occ user:info "$admin_user" >/dev/null 2>&1; then
      nextcloud-occ user:resetpassword --password-from-env "$admin_user"
    else
      nextcloud-occ user:add --password-from-env --display-name "$admin_user" "$admin_user"
    fi

    nextcloud-occ group:add admin >/dev/null 2>&1 || true
    nextcloud-occ group:adduser admin "$admin_user" >/dev/null 2>&1 || true

    if ! nextcloud-occ user:info "$admin_user" | grep -Fxq "    - admin"; then
      echo "Nextcloud admin user is not a member of the admin group" >&2
      exit 1
    fi
  '';
  nextcloudOidcProvision = pkgs.writeShellScript "nextcloud-oidc-provision" ''
    set -euo pipefail

    secret_file=${escapeShellArg oidcClientSecretFile}
    test -s "$secret_file"

    for attempt in $(seq 1 60); do
      if nextcloud-occ status >/dev/null 2>&1; then
        break
      fi
      if [ "$attempt" -eq 60 ]; then
        echo "Nextcloud did not become ready for OIDC provisioning" >&2
        exit 1
      fi
      sleep 2
    done

    nextcloud-occ app:enable user_oidc >/dev/null
    nextcloud-occ config:system:set --type=boolean --value=true allow_local_remote_servers
    nextcloud-occ config:system:set --type=string --value=https overwriteprotocol
    nextcloud-occ config:system:set --type=string --value=https://${serviceHosts.nextcloud} overwrite.cli.url
    nextcloud-occ user_oidc:provider ${escapeShellArg oidcCfg.providerId} \
      --clientid ${escapeShellArg oidcCfg.clientId} \
      --clientsecret-file "$secret_file" \
      --discoveryuri ${escapeShellArg oidcCfg.discoveryUrl} \
      --scope ${escapeShellArg (concatStringsSep " " oidcCfg.scopes)} \
      --mapping-uid ${escapeShellArg oidcCfg.mapping.uid} \
      --mapping-display-name ${escapeShellArg oidcCfg.mapping.displayName} \
      --mapping-email ${escapeShellArg oidcCfg.mapping.email} \
      --unique-uid 1 \
      --group-provisioning 0 \
      --group-restrict-login-to-whitelist 0

    nextcloud-occ config:app:set --type=string --value=1 user_oidc allow_multiple_user_backends
  '';
in
{
  config = mkIf cfg.enable {
    services.nextcloud = {
      enable = true;
      configureRedis = true;
      database.createLocally = true;
      datadir = "${appdata}/nextcloud";
      extraApps = mkIf oidcCfg.enable {
        inherit (config.services.nextcloud.package.packages.apps) user_oidc;
      };
      extraAppsEnable = true;
      home = "${appdata}/nextcloud";
      hostName = serviceHosts.nextcloud;
      https = false;
      package = pkgs.nextcloud32;
      config = {
        adminpassFile = null;
        adminuser = null;
        dbtype = "pgsql";
      };
      settings = {
        allow_local_remote_servers = true;
        "overwrite.cli.url" = "https://${serviceHosts.nextcloud}";
        overwriteprotocol = "https";
        trusted_domains = serviceHostAliases.nextcloud;
      };
    };

    systemd.services.nextcloud-admin-user = {
      description = "Ensure SOPS-backed Nextcloud admin user";
      after = [
        "network-online.target"
        "nextcloud-setup.service"
      ];
      requires = [ "nextcloud-setup.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        config.services.nextcloud.occ
        pkgs.coreutils
        pkgs.gnugrep
      ];
      restartTriggers = [ nextcloudAdminProvision ];
      serviceConfig = {
        ExecStart = nextcloudAdminProvision;
        Group = "nextcloud";
        RemainAfterExit = true;
        Type = "oneshot";
        User = "nextcloud";
      };
    };

    systemd.services.nextcloud-oidc-config = mkIf oidcCfg.enable {
      description = "Configure Nextcloud Authentik OIDC provider";
      after = [
        "network-online.target"
        "nextcloud-admin-user.service"
        "nextcloud-setup.service"
      ];
      requires = [
        "nextcloud-admin-user.service"
        "nextcloud-setup.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        config.services.nextcloud.occ
        pkgs.coreutils
      ];
      restartTriggers = [ nextcloudOidcProvision ];
      serviceConfig = {
        ExecStart = nextcloudOidcProvision;
        Group = "nextcloud";
        RemainAfterExit = true;
        Type = "oneshot";
        User = "nextcloud";
      };
    };
  };
}
