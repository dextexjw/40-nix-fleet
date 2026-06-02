{
  config,
  lib,
  pkgs,
}:

with lib;

let
  cfg = config.fleet.productivity.stack;
  appdata = cfg.appdataRoot;
  serviceHostPrefixes = {
    docs = "docs";
    firefly = "firefly";
    forgejo = "forgejo";
    freshrss = "freshrss";
    garage = "garage";
    garageWeb = "garage-web";
    gitea = "gitea";
    nextcloud = "nextcloud";
    ntfy = "ntfy";
    paperless = "paperless";
    privatebin = "privatebin";
    rustfs = "rustfs";
    rustfsConsole = "rustfs-console";
    searxng = "searxng";
    shlink = "s";
    shlinkWeb = "shlink";
    stirlingPdf = "stirling-pdf";
    syncthing = "syncthing";
    vaultwarden = "vaultwarden";
  };
  serviceHostKeys = [
    "gitea"
    "forgejo"
    "docs"
    "paperless"
    "freshrss"
    "searxng"
    "privatebin"
    "vaultwarden"
    "syncthing"
    "stirlingPdf"
    "firefly"
    "nextcloud"
    "garage"
    "garageWeb"
    "rustfs"
    "rustfsConsole"
    "shlink"
    "shlinkWeb"
    "ntfy"
  ];
  mkServiceHostNames =
    domains:
    mapAttrs (
      _name: prefix:
      map (serviceDomain: "${prefix}.${serviceDomain}") domains
    ) serviceHostPrefixes;
  mkServiceHosts = domains: mapAttrs (_name: names: head names) (mkServiceHostNames domains);
  mkServiceHostAliases = domains: mapAttrs (_name: names: tail names) (mkServiceHostNames domains);
  serviceHosts = cfg.serviceHosts;
  serviceHostAliases = mkServiceHostAliases cfg.serviceDomains;
  serviceRouteLines = concatStringsSep "\n" (
    concatMap (
      serviceKey:
      map (hostName: "        http://${hostName}") ([ serviceHosts.${serviceKey} ] ++ serviceHostAliases.${serviceKey})
    ) serviceHostKeys
  );
  rustfsGid = 10001;
  rustfsUid = 10001;

  secretPath =
    name:
    if cfg.secrets.enable then
      config.sops.secrets.${name}.path
    else
      "/run/secrets/${name}";

  smbCredentialsFile = secretPath "smb-credentials";
  resticPasswordFile = secretPath "restic-password";

  garageEnvironmentFile = pkgs.writeText "garage.env" ''
    GARAGE_LOG_TO_JOURNALD=true
  '';

  mkdocsEnv = pkgs.python3.withPackages (
    pythonPackages: with pythonPackages; [
      mkdocs
      mkdocs-material
    ]
  );

  mkdocsRoot = "${appdata}/mkdocs";
  mkdocsConfig = pkgs.writeText "mkdocs.yml" ''
    site_name: Homelab Knowledge Base
    site_url: http://${serviceHosts.docs}/
    theme:
      name: material
    nav:
      - Home: index.md
  '';
  mkdocsIndex = pkgs.writeText "index.md" ''
    # Homelab Knowledge Base

    This internal documentation site is backed by Material for MkDocs.
  '';

  systemdMountOptions = filter (
    option:
    option != "_netdev"
    && option != "noauto"
    && option != "nofail"
    && !(hasPrefix "x-systemd." option)
  ) cfg.smb.mountOptions;

  appsdataDirs = [
    appdata
  ];

  statefulServices = [
    "gitea.service"
    "forgejo.service"
    "nginx.service"
    "paperless-scheduler.service"
    "paperless-task-queue.service"
    "paperless-consumer.service"
    "paperless-web.service"
    "freshrss-config.service"
    "freshrss-updater.service"
    "phpfpm-freshrss.service"
    "searx.service"
    "vaultwarden.service"
    "phpfpm-privatebin.service"
    "syncthing.service"
    "stirling-pdf.service"
    "phpfpm-firefly-iii.service"
    "firefly-iii-cron.timer"
    "phpfpm-nextcloud.service"
    "garage.service"
    "podman-shlink.service"
    "podman-shlink-web.service"
    "podman-rustfs.service"
    "ntfy-sh.service"
  ];
in
{
  inherit
    appdata
    appsdataDirs
    cfg
    garageEnvironmentFile
    mkdocsConfig
    mkdocsEnv
    mkdocsIndex
    mkdocsRoot
    resticPasswordFile
    rustfsGid
    rustfsUid
    secretPath
    serviceHostAliases
    serviceHosts
    serviceRouteLines
    smbCredentialsFile
    statefulServices
    systemdMountOptions
    ;
}
