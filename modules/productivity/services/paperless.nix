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
  paperlessHostNames = [ serviceHosts.paperless ] ++ serviceHostAliases.paperless;
  paperlessOrigin = hostName: "${if hasSuffix ".h" hostName then "http" else "https"}://${hostName}";
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
      settings = {
        PAPERLESS_ADMIN_USER = "smoke";
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
  };
}
