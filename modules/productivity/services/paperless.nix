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
  oidcCfg = cfg.paperless.oidc;
  oidcAdminConfig = pkgs.writeText "paperless-oidc-admin-users.json" (
    builtins.toJSON {
      emailFile = oidcCfg.adminEmailFile;
      providerId = oidcCfg.providerId;
      usernameFile = oidcCfg.adminUsernameFile;
    }
  );
  oidcSuperuserScript = pkgs.writeText "paperless-oidc-superusers.py" ''
    import json

    from django.contrib.auth.models import User

    try:
        from allauth.socialaccount.models import SocialAccount
    except Exception:
        SocialAccount = None

    with open("${oidcAdminConfig}", encoding="utf-8") as config_file:
        admin_config = json.load(config_file)

    def read_secret(path):
        with open(path, encoding="utf-8") as secret_file:
            return secret_file.readline().strip()


    admin_emails = {read_secret(admin_config["emailFile"])} - {""}
    admin_provider_id = admin_config["providerId"]
    admin_usernames = {read_secret(admin_config["usernameFile"])} - {""}
    oidc_provider_names = {"openid_connect", admin_provider_id}
    users = {}


    def add_user(user):
        if user is not None:
            users[user.pk] = user


    for user in User.objects.filter(username__in=admin_usernames):
        add_user(user)

    for user in User.objects.filter(email__in=admin_emails):
        add_user(user)

    if SocialAccount is not None:
        for account in SocialAccount.objects.select_related("user").all():
            if account.provider not in oidc_provider_names and not account.provider.startswith(
                "openid_connect",
            ):
                continue
            extra_data = account.extra_data or {}
            sources = [
                extra_data,
                extra_data.get("userinfo") or {},
                extra_data.get("id_token") or {},
            ]
            values = {
                value
                for source in sources
                for value in (
                    source.get("email"),
                    source.get("preferred_username"),
                    source.get("username"),
                )
                if value
            }
            if values & (admin_emails | admin_usernames):
                add_user(account.user)

    promoted = []
    for user in users.values():
        changed = False
        if not user.is_staff:
            user.is_staff = True
            changed = True
        if not user.is_superuser:
            user.is_superuser = True
            changed = True
        if changed:
            user.save(update_fields=["is_staff", "is_superuser"])
            promoted.append(user.username)

    if promoted:
        print("promoted Paperless OIDC admin users: " + ", ".join(sorted(promoted)))
    else:
        print("Paperless OIDC admin users already promoted or not present yet")
  '';
  paperlessHostNames = [ serviceHosts.paperless ] ++ serviceHostAliases.paperless;
  paperlessOrigin = hostName: "${if hasSuffix ".h" hostName then "http" else "https"}://${hostName}";
  paperlessPackageWithDisabledTest =
    pkg:
    (pkg.overridePythonAttrs (oldAttrs: {
      # Upstream 2.20.15 has one failing mail-rule test under nixpkgs Python 3.13;
      # keep the rest of the package test suite enabled.
      disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_error_skip_rule" ];
    }))
    // {
      override = args: paperlessPackageWithDisabledTest (pkg.override args);
    };
  paperlessPackage = paperlessPackageWithDisabledTest pkgs.paperless-ngx;
in
{
  config = mkIf cfg.enable {
    services.paperless = {
      enable = true;
      address = "127.0.0.1";
      configureNginx = true;
      consumptionDir = "${appdata}/paperless/consume";
      dataDir = "${appdata}/paperless";
      database.createLocally = true;
      domain = serviceHosts.paperless;
      environmentFile = mkIf oidcCfg.enable oidcCfg.environmentFile;
      mediaDir = "${appdata}/paperless/media";
      passwordFile = secretPath "paperless-admin-password";
      package = paperlessPackage;
      settings = {
        PAPERLESS_ALLOWED_HOSTS = concatStringsSep "," paperlessHostNames;
        PAPERLESS_CSRF_TRUSTED_ORIGINS = concatStringsSep "," (map paperlessOrigin paperlessHostNames);
        PAPERLESS_OCR_LANGUAGE = "eng";
        PAPERLESS_URL = mkForce (paperlessOrigin serviceHosts.paperless);
      }
      // optionalAttrs oidcCfg.enable {
        PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
        PAPERLESS_LOGOUT_REDIRECT_URL = "https://auth.jax22.com/application/o/paperless/end-session/";
        PAPERLESS_SOCIAL_AUTO_SIGNUP = true;
        PAPERLESS_SOCIALACCOUNT_ALLOW_SIGNUPS = true;
      };
    };

    systemd.services.paperless-oidc-superuser = mkIf oidcCfg.enable {
      description = "Promote configured Paperless Authentik OIDC users to superuser";
      after = [
        "paperless-web.service"
        "postgresql.service"
      ];
      requires = [ "paperless-web.service" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        /run/current-system/sw/bin/paperless-manage shell < ${oidcSuperuserScript}
      '';
      serviceConfig = {
        EnvironmentFile = oidcCfg.environmentFile;
        Group = "paperless";
        Type = "oneshot";
        User = "paperless";
      };
    };

    systemd.timers.paperless-oidc-superuser = mkIf oidcCfg.enable {
      description = "Retry Paperless Authentik OIDC superuser promotion";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        Persistent = true;
        Unit = "paperless-oidc-superuser.service";
      };
    };
  };
}
