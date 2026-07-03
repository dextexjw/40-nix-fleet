{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  testbedLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg appdata serviceHosts;
  oidcCfg = cfg.gitea.oidc;
  giteaService = config.services.gitea;
  awk = lib.getExe pkgs.gawk;
  giteaCommand = "${lib.getExe giteaService.package} --config ${escapeShellArg "${giteaService.customDir}/conf/app.ini"} --work-path ${escapeShellArg giteaService.stateDir}";
  giteaOidcProvision = pkgs.writeShellScript "gitea-oidc-provision" ''
    set -euo pipefail

    client_secret="$(<${escapeShellArg oidcCfg.clientSecretFile})"
    if [ -z "$client_secret" ]; then
      echo "Gitea OIDC client secret is empty" >&2
      exit 1
    fi

    source_id="$(
      ${giteaCommand} admin auth list --vertical-bars --padding 1 --pad-char ' ' \
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
      ${giteaCommand} admin auth update-oauth --id "$source_id" "''${common_args[@]}"
      echo "updated Gitea OIDC auth source ${oidcCfg.authName}"
    else
      ${giteaCommand} admin auth add-oauth "''${common_args[@]}"
      echo "created Gitea OIDC auth source ${oidcCfg.authName}"
    fi
  '';
in
{
  config = mkIf (cfg.enable && cfg.gitea.enable) {
    assertions = [
      {
        assertion = !oidcCfg.enable || oidcCfg.clientSecretFile != null;
        message = "fleet.testbed.stack.gitea.oidc.clientSecretFile must be set when Gitea OIDC is enabled.";
      }
    ];

    services.postgresql.enable = true;

    services.gitea = {
      enable = true;
      appName = "Fleet Git";
      lfs.enable = true;
      stateDir = "${appdata}/gitea";
      database = {
        type = "postgres";
        createDatabase = true;
      };
      dump = {
        enable = true;
        backupDir = "${appdata}/gitea/dump";
        type = "tar.zst";
      };
      settings = {
        oauth2_client = mkIf oidcCfg.enable {
          ACCOUNT_LINKING = "login";
          ENABLE_AUTO_REGISTRATION = true;
          OPENID_CONNECT_SCOPES = concatStringsSep " " oidcCfg.scopes;
          UPDATE_AVATAR = true;
          USERNAME = "nickname";
        };
        repository.DEFAULT_BRANCH = "main";
        server = {
          DOMAIN = serviceHosts.gitea;
          HTTP_ADDR = "0.0.0.0";
          HTTP_PORT = cfg.ports.gitea;
          ROOT_URL = "https://${serviceHosts.gitea}/";
          SSH_PORT = 22;
        };
        service = {
          DISABLE_REGISTRATION = true;
          REQUIRE_SIGNIN_VIEW = false;
        };
      };
    };

    systemd.services.gitea-oidc-config = mkIf oidcCfg.enable {
      description = "Configure Gitea Authentik OIDC login source";
      after = [
        "gitea.service"
        "network-online.target"
      ];
      requires = [ "gitea.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ giteaOidcProvision ];
      serviceConfig = {
        ExecStart = giteaOidcProvision;
        Group = "gitea";
        RemainAfterExit = true;
        Type = "oneshot";
        User = "gitea";
      };
    };
  };
}
