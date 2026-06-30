{
  config,
  lib,
  ...
}:

let
  hosts = import ../../hosts.nix;
  gatewayCluster = import ../../lib/gateway-cluster.nix { inherit hosts; };
  host = hosts.testbed-vm;
  serviceDomains = (import ../../lib/service-domains.nix).all;
  serviceDomain = builtins.head serviceDomains;
  exposure = import ../../lib/exposure.nix {
    inherit lib;
    root = ../..;
  };
  exposureCatalog = exposure.load {
    inherit hosts serviceDomain serviceDomains;
  };
  routeServices = builtins.filter (service: service ? route) exposureCatalog.serviceEntries;
  routeHosts = lib.unique (lib.concatMap (service: service.route.hosts) routeServices);
  secretsFile = ../../secrets/secrets.yaml;
  secretsEnabled = builtins.pathExists secretsFile;
in
{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/testbed
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  fleet.host.name = "testbed-vm";
  users.motd = "testbed-vm: Listmonk newsletter testbed, MailHog SMTP capture, and appdata backups";

  networking.hosts.${gatewayCluster.clientAddress} = routeHosts;

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
      checkmate-capture-environment = {
        restartUnits = [ "checkmate-capture.service" ];
      };
      listmonk-admin-password = {
        restartUnits = [ "listmonk.service" ];
      };
      listmonk-admin-username = {
        restartUnits = [ "listmonk.service" ];
      };
      listmonk-oidc-client-secret = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [ "listmonk-oidc-config.service" ];
      };
      restic-password = {
        restartUnits = [ "testbed-appdata-backup.service" ];
      };
      smb-credentials = { };
    };
    templates."listmonk-environment" = {
      content = ''
        LISTMONK_ADMIN_USER='${config.sops.placeholder."listmonk-admin-username"}'
        LISTMONK_ADMIN_PASSWORD='${config.sops.placeholder."listmonk-admin-password"}'
      '';
      owner = "listmonk";
      group = "listmonk";
      mode = "0400";
      restartUnits = [ "listmonk.service" ];
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "systemd-journal"
      "testbed"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.testbed.stack = {
    enable = true;
    gatewayAddresses = gatewayCluster.addresses;
    listmonk = {
      adminEnvironmentFile =
        if secretsEnabled then
          config.sops.templates."listmonk-environment".path
        else
          "/run/secrets/listmonk-environment";
      bindAddress = host.ip;
      oidcClientSecretFile =
        if secretsEnabled then
          config.sops.secrets.listmonk-oidc-client-secret.path
        else
          "/run/secrets/listmonk-oidc-client-secret";
    };
    secrets.enable = secretsEnabled;
    inherit serviceDomains;
    smb.backupDevice = "//nas.home.arpa/backups";
  };
}
