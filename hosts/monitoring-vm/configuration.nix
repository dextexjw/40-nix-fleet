{
  config,
  lib,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.monitoring-vm;
  serviceDomains = (import ../../lib/service-domains.nix).all;
  serviceDomain = builtins.head serviceDomains;
  exposure = import ../../lib/exposure.nix {
    inherit lib;
    root = ../..;
  };
  exposureCatalog = exposure.load {
    inherit hosts serviceDomain serviceDomains;
  };
  secretsFile = ../../secrets/secrets.yaml;
  secretsEnabled = builtins.pathExists secretsFile;
  checkmateInterval = 60000;
  capturePort = 59232;
  routeScheme = hostName: if builtins.match ".*[.]h" hostName != null then "http" else "https";
  routeServices = builtins.filter (service: service ? route) exposureCatalog.serviceEntries;
  routeHosts = lib.unique (lib.concatMap (service: service.route.hosts) routeServices);
  parseBackend =
    service:
    let
      parsed = builtins.match "https?://([^/:]+):([0-9]+).*" service.route.url;
    in
    if parsed == null then
      throw "unable to parse backend URL for ${service.id}: ${service.route.url}"
    else
      {
        host = builtins.elemAt parsed 0;
        port = builtins.fromJSON (builtins.elemAt parsed 1);
      };
  mkServiceMonitor =
    service:
    let
      smokeHttp = if service ? smoke && service.smoke ? http then service.smoke.http else null;
      primaryHost = builtins.head service.route.hosts;
      backend = parseBackend service;
    in
    {
      description = service.route.description;
      group = service.group;
      id = service.id;
      interval = checkmateInterval;
      name = service.name;
    }
    // (
      if smokeHttp != null then
        {
          port = null;
          type = "http";
          url = "${routeScheme primaryHost}://${primaryHost}${smokeHttp.path or "/"}";
        }
      else
        {
          port = backend.port;
          type = "port";
          url = backend.host;
        }
    );
  hostNames = lib.sort (left: right: left < right) (builtins.attrNames hosts);
  mkHardwareMonitor =
    name:
    let
      targetHost = hosts.${name};
    in
    {
      description = "Checkmate Capture hardware monitor for ${name}";
      group = "Hosts";
      id = name;
      interval = checkmateInterval;
      name = name;
      url = "http://${targetHost.ip}:${toString capturePort}/api/v1/metrics";
    };
in

{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/monitoring/checkmate-provisioning.nix
    ../../modules/monitoring/stack.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "monitoring-vm";
  networking.domain = host.domain;
  users.motd = "monitoring-vm: Checkmate, Beszel, host agents, and appdata backups";

  # ============================================================================
  # SECRETS
  # ============================================================================

  sops = lib.mkIf secretsEnabled {
    defaultSopsFile = secretsFile;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      admin-password-hash = {
        neededForUsers = true;
      };
      beszel-agent-key = {
        owner = "beszel-agent";
        group = "beszel-agent";
        mode = "0400";
        restartUnits = [ "beszel-agent.service" ];
      };
      beszel-agent-token = {
        owner = "beszel-agent";
        group = "beszel-agent";
        mode = "0400";
        restartUnits = [ "beszel-agent.service" ];
      };
      beszel-oidc-client-secret = {
        owner = "beszel-hub";
        group = "beszel-hub";
        mode = "0400";
        restartUnits = [
          "beszel-hub-oidc-config.service"
          "beszel-hub.service"
        ];
      };
      checkmate-capture-environment = {
        restartUnits = [ "checkmate-capture.service" ];
      };
      checkmate-environment = {
        restartUnits = [ "podman-checkmate.service" ];
      };
      checkmate-provisioning-credentials = {
        restartUnits = [ "checkmate-provisioning.service" ];
      };
      restic-password = {
        restartUnits = [ "monitoring-appdata-backup.service" ];
      };
      smb-credentials = { };
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "monitoring"
      "systemd-journal"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.monitoring.stack = {
    beszel.oidc = {
      clientSecretFile = config.sops.secrets.beszel-oidc-client-secret.path;
      enable = true;
    };
    enable = true;
    secrets.enable = secretsEnabled;
    inherit serviceDomains;
    smb.backupDevice = "//nas.home.arpa/backups";
  };

  fleet.monitoring.checkmateProvisioning = {
    baseUrl = "http://127.0.0.1:52345/api/v1";
    captureEnvironmentFile =
      if secretsEnabled then
        config.sops.secrets.checkmate-capture-environment.path
      else
        "/run/secrets/checkmate-capture-environment";
    credentialsFile =
      if secretsEnabled then
        config.sops.secrets.checkmate-provisioning-credentials.path
      else
        "/run/secrets/checkmate-provisioning-credentials";
    enable = secretsEnabled;
    hardwareMonitors = map mkHardwareMonitor hostNames;
    serviceMonitors = map mkServiceMonitor routeServices;
  };

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking.networkmanager.enable = lib.mkForce false;
  networking.hosts.${hosts.gateway-vm.ip} = routeHosts;
  networking.useDHCP = lib.mkForce false;
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = [
        "en*"
        "eth*"
      ];
      networkConfig = {
        Address = "${host.ip}/24";
        DNS = host.nameservers;
        Domains = [
          host.domain
          "~${host.domain}"
        ];
        Gateway = host.gateway;
      };
    };
  };

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = host.vm.disk;
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  time.timeZone = host.timezone;
  system.stateVersion = "25.11";
}
