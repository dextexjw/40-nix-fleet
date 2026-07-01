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

  homeboxCfg = cfg.homebox;
  homeboxExternalHost = removePrefix "http://" (
    removePrefix "https://" (removeSuffix "/" homeboxCfg.externalUrl)
  );
  homebox_0_26_2 =
    let
      version = "0.26.2";
      src = pkgs.fetchFromGitHub {
        owner = "sysadminsmedia";
        repo = "homebox";
        tag = "v${version}";
        hash = "sha256-JUhRpUWbydy28Xw7j6oCKJLBmaOxcruWAdkqm+hvouY=";
      };
    in
    pkgs.homebox.overrideAttrs (_old: {
      inherit version src;
      vendorHash = "sha256-peQaPSbxGn8MnbZPqCi5ptW+dMh9l4W1hB6HqBLTqh4=";
      pnpmDeps = pkgs.fetchPnpmDeps {
        pname = "homebox";
        inherit version;
        src = "${src}/frontend";
        pnpm = pkgs.pnpm_10;
        fetcherVersion = 3;
        hash = "sha256-oHS2uMWyuqpiK7yWznmZ2mgxPJpWsyOZL2wz6zBu0cc=";
      };
      ldflags = [
        "-s"
        "-w"
        "-extldflags=-static"
        "-X main.version=v${version}"
        "-X main.commit=v${version}"
      ];
    });
in
{
  config = mkIf cfg.enable {
    fleet.testbed.stack.homebox.package = mkDefault homebox_0_26_2;

    services.homebox = {
      enable = true;
      package = homeboxCfg.package;
      settings = {
        HBOX_DATABASE_DRIVER = "sqlite3";
        HBOX_DATABASE_SQLITE_PATH = "${homeboxCfg.stateDir}/data/homebox.db?_pragma=busy_timeout=999&_pragma=journal_mode=WAL&_fk=1&_time_format=sqlite";
        HBOX_MAILER_FROM = "homebox@testbed.home.arpa";
        HBOX_MAILER_HOST = "127.0.0.1";
        HBOX_MAILER_PORT = toString cfg.ports.mailpitSmtp;
        HBOX_MODE = "production";
        HBOX_OIDC_AUTO_REDIRECT = "false";
        HBOX_OIDC_BUTTON_TEXT = "Sign in with Authentik";
        HBOX_OIDC_CLIENT_ID = homeboxCfg.oidcClientId;
        HBOX_OIDC_EMAIL_CLAIM = "email";
        HBOX_OIDC_EMAIL_VERIFIED_CLAIM = "email_verified";
        HBOX_OIDC_ENABLED = "true";
        HBOX_OIDC_ISSUER_URL = homeboxCfg.oidcIssuerUrl;
        HBOX_OIDC_NAME_CLAIM = "name";
        HBOX_OIDC_SCOPE = "openid profile email";
        HBOX_OIDC_VERIFY_EMAIL = "false";
        HBOX_OPTIONS_ALLOW_ANALYTICS = "false";
        HBOX_OPTIONS_ALLOW_LOCAL_LOGIN = boolToString homeboxCfg.allowLocalLogin;
        HBOX_OPTIONS_ALLOW_REGISTRATION = boolToString homeboxCfg.allowRegistration;
        HBOX_OPTIONS_CHECK_GITHUB_RELEASE = "false";
        HBOX_OPTIONS_GITHUB_RELEASE_CHECK = "false";
        HBOX_OPTIONS_HOSTNAME = homeboxExternalHost;
        HBOX_OPTIONS_TRUST_PROXY = "true";
        HBOX_STORAGE_CONN_STRING = "file://${homeboxCfg.stateDir}";
        HBOX_STORAGE_PREFIX_PATH = "data";
        HBOX_WEB_HOST = homeboxCfg.bindAddress;
        HBOX_WEB_PORT = toString cfg.ports.homebox;
        HOME = toString homeboxCfg.stateDir;
        TMPDIR = "${homeboxCfg.stateDir}/tmp";
      };
    };

    systemd.services.homebox = {
      after = [
        "mailpit-testbed.service"
        "network-online.target"
        "systemd-tmpfiles-setup.service"
      ];
      requires = [
        "mailpit-testbed.service"
        "systemd-tmpfiles-setup.service"
      ];
      wants = [ "network-online.target" ];
      preStart = mkForce ''
        ${pkgs.coreutils}/bin/rm -rf ${escapeShellArg (toString "${homeboxCfg.stateDir}/tmp")}
        ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg (toString "${homeboxCfg.stateDir}/tmp")}
      '';
      serviceConfig = {
        EnvironmentFile = toString homeboxCfg.environmentFile;
        ReadWritePaths = [ (toString homeboxCfg.stateDir) ];
        StateDirectory = mkForce [ ];
        UMask = mkForce "0077";
        WorkingDirectory = toString homeboxCfg.stateDir;
      };
    };
  };
}
