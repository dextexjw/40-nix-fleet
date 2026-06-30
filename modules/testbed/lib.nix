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
    listmonk = "listmonk";
  };
  serviceHostKeys = [ "listmonk" ];
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
    "listmonk.service"
    "postgresql.service"
    "mailhog.service"
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
