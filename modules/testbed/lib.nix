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
    fizzy = "fizzy";
    homebox = "homebox";
    kaneo = "kaneo";
    keeper = "keeper";
    listmonk = "listmonk";
    mailpit = "mailpit";
    plane = "plane";
    sure = "sure";
  };
  serviceHostKeys = [
    "fizzy"
    "homebox"
    "kaneo"
    "keeper"
    "listmonk"
    "mailpit"
    "plane"
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
    "podman-fizzy.service"
    "homebox.service"
    "podman-kaneo.service"
    "podman-keeper.service"
    "redis-keeper.service"
    "listmonk.service"
    "nginx.service"
    "plane-admin-bootstrap.service"
    "plane-migrate.service"
    "plane-rabbitmq-config.service"
    "podman-plane-api.service"
    "podman-plane-beat-worker.service"
    "podman-plane-live.service"
    "podman-plane-rabbitmq.service"
    "podman-plane-worker.service"
    "podman-sure-web.service"
    "podman-sure-worker.service"
    "postgresql.service"
    "redis-sure.service"
    "mailpit-testbed.service"
  ];
in
{
  inherit
    appdata
    cfg
    resticPasswordFile
    secretPath
    serviceHosts
    serviceRouteLines
    smbCredentialsFile
    statefulServices
    systemdMountOptions
    ;
}
