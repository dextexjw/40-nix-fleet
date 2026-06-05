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
  inherit (productivityLib) cfg appdata serviceHosts;
  oidcCfg = cfg.forgejo.oidc;
  forgejoService = config.services.forgejo;
  awk = lib.getExe pkgs.gawk;
  forgejoCommand = "${lib.getExe forgejoService.package} --config ${escapeShellArg "${forgejoService.customDir}/conf/app.ini"} --work-path ${escapeShellArg forgejoService.stateDir}";
  forgejoOidcProvision = pkgs.writeShellScript "forgejo-oidc-provision" ''
    set -euo pipefail

    client_secret="$(<${escapeShellArg oidcCfg.clientSecretFile})"
    if [ -z "$client_secret" ]; then
      echo "Forgejo OIDC client secret is empty" >&2
      exit 1
    fi

    source_id="$(
      ${forgejoCommand} admin auth list --vertical-bars --padding 1 --pad-char ' ' \
        | ${awk} -F '|' -v name=${escapeShellArg oidcCfg.authName} '
            NR == 1 { next }
            {
              for (i = 1; i <= NF; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
              }
              if ($2 == name) {
                print $1
                exit
              }
            }
          '
    )"

    common_args=(
      --name ${escapeShellArg oidcCfg.authName}
      --provider openidConnect
      --key ${escapeShellArg oidcCfg.clientId}
      --secret "$client_secret"
      --auto-discover-url ${escapeShellArg oidcCfg.autoDiscoverUrl}
      --icon-url ${escapeShellArg oidcCfg.iconUrl}
    )
    ${concatMapStringsSep "\n    " (
      scope: "common_args+=(--scopes ${escapeShellArg scope})"
    ) oidcCfg.scopes}

    if [ -n "$source_id" ]; then
      ${forgejoCommand} admin auth update-oauth --id "$source_id" "''${common_args[@]}"
      echo "updated Forgejo OIDC auth source ${oidcCfg.authName}"
    else
      ${forgejoCommand} admin auth add-oauth "''${common_args[@]}"
      echo "created Forgejo OIDC auth source ${oidcCfg.authName}"
    fi
  '';
in
{
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !oidcCfg.enable || oidcCfg.clientSecretFile != null;
        message = "fleet.productivity.stack.forgejo.oidc.clientSecretFile must be set when Forgejo OIDC is enabled.";
      }
    ];

    services.forgejo = {
      enable = true;
      package = pkgs.forgejo;
      lfs.enable = true;
      stateDir = "${appdata}/forgejo";
      database = {
        type = "postgres";
        createDatabase = true;
      };
      dump = {
        enable = true;
        backupDir = "${appdata}/forgejo/dump";
        type = "tar.zst";
      };
      settings = {
        DEFAULT.APP_NAME = "Fleet Forgejo";
        oauth2_client = mkIf oidcCfg.enable {
          ACCOUNT_LINKING = "login";
          ENABLE_AUTO_REGISTRATION = true;
          OPENID_CONNECT_SCOPES = concatStringsSep " " oidcCfg.scopes;
          UPDATE_AVATAR = true;
          USERNAME = "nickname";
        };
        repository.DEFAULT_BRANCH = "main";
        server = {
          DOMAIN = serviceHosts.forgejo;
          HTTP_ADDR = "0.0.0.0";
          HTTP_PORT = cfg.ports.forgejo;
          ROOT_URL = "https://${serviceHosts.forgejo}/";
          SSH_PORT = 22;
        };
        service = {
          DISABLE_REGISTRATION = true;
          REQUIRE_SIGNIN_VIEW = false;
        };
      };
    };

    systemd.services.forgejo-oidc-config = mkIf oidcCfg.enable {
      description = "Configure Forgejo Authentik OIDC login source";
      after = [
        "forgejo.service"
        "network-online.target"
      ];
      requires = [ "forgejo.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ forgejoOidcProvision ];
      serviceConfig = {
        ExecStart = forgejoOidcProvision;
        Group = "forgejo";
        RemainAfterExit = true;
        Type = "oneshot";
        User = "forgejo";
      };
    };
  };
}
