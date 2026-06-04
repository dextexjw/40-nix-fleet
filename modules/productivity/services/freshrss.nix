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
  adminUsernameFile = secretPath "freshrss-admin-username";
  adminPasswordFile = secretPath "freshrss-admin-password";
in
{
  config = mkIf cfg.enable {
    services.freshrss = {
      enable = true;
      api.enable = true;
      authType = "form";
      baseUrl = "http://${serviceHosts.freshrss}";
      dataDir = "${appdata}/freshrss";
      passwordFile = adminPasswordFile;
      virtualHost = serviceHosts.freshrss;
      webserver = "nginx";
    };

    systemd.services.freshrss-config.script = mkForce ''
      set -euo pipefail

      IFS= read -r admin_user < ${adminUsernameFile} || [ -n "$admin_user" ]
      test -n "$admin_user"

      configure_freshrss() {
        "$@" --api-enabled \
          --auth-type "form" \
          --base-url "http://${serviceHosts.freshrss}" \
          --db-base "freshrss" \
          --db-host "localhost" \
          --db-type "sqlite" \
          --db-user "freshrss" \
          --default-user "$admin_user" \
          --language "en"
      }

      if test -f ${appdata}/freshrss/config.php; then
        configure_freshrss ./cli/reconfigure.php
        ./cli/update-user.php --user "$admin_user" --password "$(<${adminPasswordFile})"
      else
        ./cli/prepare.php
        configure_freshrss ./cli/do-install.php
        ./cli/create-user.php --user "$admin_user" --password "$(<${adminPasswordFile})"
      fi
    '';
  };
}
