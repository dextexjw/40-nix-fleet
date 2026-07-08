{
  config,
  lib,
  pkgs,
}:

with lib;

let
  cfg = config.fleet.testbed.stack;
  appdata = cfg.appdataRoot;
  serviceHostPrefixes = {
    affine = "affine";
    firefly = "firefly";
    fizzy = "fizzy";
    gitea = "gitea";
    homebox = "homebox";
    invoiceplane = "invoiceplane";
    kaneo = "kaneo";
    keeper = "keeper";
    listmonk = "listmonk";
    mailpit = "mailpit";
    outline = "outline";
    plane = "plane";
    postiz = "postiz";
    stirlingPdf = "stirling-pdf";
    sure = "sure";
  };
  serviceHostKeys = [
    "affine"
    "firefly"
    "fizzy"
    "gitea"
    "homebox"
    "invoiceplane"
    "kaneo"
    "keeper"
    "listmonk"
    "mailpit"
    "outline"
    "plane"
    "postiz"
    "stirlingPdf"
    "sure"
  ];
  mkServiceHostNames =
    domains:
    mapAttrs (
      _name: prefix: map (serviceDomain: "${prefix}.${serviceDomain}") domains
    ) serviceHostPrefixes;
  mkServiceHostAliases = domains: mapAttrs (_name: names: tail names) (mkServiceHostNames domains);
  serviceHosts = cfg.serviceHosts;
  serviceHostAliases = mkServiceHostAliases cfg.serviceDomains;
  serviceRouteLines = concatStringsSep "\n" (
    concatMap (
      serviceKey:
      map (hostName: "        http://${hostName}") (
        [ serviceHosts.${serviceKey} ] ++ serviceHostAliases.${serviceKey}
      )
    ) serviceHostKeys
  );

  secretPath =
    name: if cfg.secrets.enable then config.sops.secrets.${name}.path else "/run/secrets/${name}";

  smbCredentialsFile = secretPath "smb-credentials";
  resticPasswordFile = secretPath "restic-password";

  systemdMountOptions = filter (
    option:
    option != "_netdev" && option != "noauto" && option != "nofail" && !(hasPrefix "x-systemd." option)
  ) cfg.smb.mountOptions;

  statefulServices = [
    "redis-affine.service"
    "podman-affine.service"
    "gitea.service"
    "podman-fizzy.service"
    "homebox.service"
    "phpfpm-firefly-iii.service"
    "firefly-iii-cron.timer"
    "phpfpm-invoiceplane.service"
    "invoiceplane-bootstrap.service"
    "podman-kaneo.service"
    "podman-keeper.service"
    "redis-keeper.service"
    "listmonk.service"
    "podman-metube.service"
    "podman-outline.service"
    "redis-outline.service"
    "nginx.service"
    "plane-admin-bootstrap.service"
    "plane-migrate.service"
    "plane-rabbitmq-config.service"
    "podman-plane-api.service"
    "podman-plane-beat-worker.service"
    "podman-plane-live.service"
    "podman-plane-rabbitmq.service"
    "podman-plane-worker.service"
    "podman-postiz.service"
    "podman-postiz-postgres.service"
    "podman-postiz-redis.service"
    "podman-postiz-temporal.service"
    "podman-postiz-temporal-elasticsearch.service"
    "podman-postiz-temporal-postgres.service"
    "stirling-pdf.service"
    "podman-sure-web.service"
    "podman-sure-worker.service"
    "postgresql.service"
    "redis-sure.service"
    "mailpit-testbed.service"
    "mysql.service"
  ];
in
{
  inherit
    appdata
    cfg
    resticPasswordFile
    secretPath
    serviceHostAliases
    serviceHosts
    serviceRouteLines
    smbCredentialsFile
    statefulServices
    systemdMountOptions
    ;
}
