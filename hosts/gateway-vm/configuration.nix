{
  config,
  lib,
  pkgs,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.gateway-vm;
  domain = host.domain;
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
  technitium-dns-server-library_15_2_0 =
    pkgs.callPackage ../../modules/gateway/technitium/library-package.nix
      { };
  technitium-dns-server_15_2_0 = pkgs.callPackage ../../modules/gateway/technitium/package.nix {
    technitium-dns-server-library = technitium-dns-server-library_15_2_0;
  };
  homepage-dashboard_1_13_1 = pkgs.homepage-dashboard.overrideAttrs (
    finalAttrs: previousAttrs: rec {
      version = "1.13.1";

      src = pkgs.fetchFromGitHub {
        owner = "gethomepage";
        repo = "homepage";
        tag = "v${version}";
        hash = "sha256-RKvBzHtxK/VNdSRoJSUiVmckG7jTTH75SEe6aX2xq1E=";
      };

      pnpmDeps = pkgs.fetchPnpmDeps {
        pname = previousAttrs.pname;
        inherit version src;
        pnpm = pkgs.pnpm_10;
        fetcherVersion = 3;
        hash = "sha256-xd7F39WBSAy3ozJjI12XB+oGvijSGHIMYwQhdpaO/l8=";
      };
    }
  );
  traefik_3_7_1 = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "traefik";
    version = "3.7.1";

    src = pkgs.fetchurl {
      url = "https://github.com/traefik/traefik/releases/download/v${version}/traefik_v${version}_linux_amd64.tar.gz";
      hash = "sha256-6SvPsD+h5qcMTnrU608WBJZ+b6PCHY52BaylQHpAFiw=";
    };

    unpackPhase = ''
      runHook preUnpack

      tar -xzf "$src"

      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      install -Dm0755 traefik "$out/bin/traefik"

      runHook postInstall
    '';

    meta = {
      description = "Cloud native application proxy";
      homepage = "https://traefik.io/";
      license = lib.licenses.mit;
      mainProgram = "traefik";
      platforms = [ "x86_64-linux" ];
    };
  };
in

{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/gateway/gluetun.nix
    ../../modules/gateway/homepage.nix
    ../../modules/gateway/netbird.nix
    ../../modules/gateway/netbootxyz.nix
    ../../modules/gateway/state-backup.nix
    ../../modules/gateway/tailscale.nix
    ../../modules/gateway/technitium
    ../../modules/gateway/traefik.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "gateway-vm";
  networking.domain = host.domain;
  users.motd = "gateway-vm: Traefik ingress, Homepage, Technitium DNS, Gluetun VPN proxy, netboot.xyz, NetBird, and Tailscale";

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
      gluetun-control-api-key = {
        restartUnits = [
          "gluetun-control-auth-config.service"
          "podman-gluetun.service"
          "podman-gluetun-webui.service"
        ];
      };
      gluetun-openvpn-password = {
        restartUnits = [ "podman-gluetun.service" ];
      };
      gluetun-openvpn-username = {
        restartUnits = [ "podman-gluetun.service" ];
      };
      restic-password = {
        restartUnits = [ "gateway-state-backup.service" ];
      };
      smb-credentials = { };
      technitium-admin-password = {
        restartUnits = [ "technitium-dns-configure.service" ];
      };
      technitium-admin-username = {
        restartUnits = [ "technitium-dns-configure.service" ];
      };
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "systemd-journal"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.gateway.gluetun = {
    bindAddress = host.ip;
    controlServer = {
      apiKeyFile = config.sops.secrets.gluetun-control-api-key.path;
      enable = true;
    };
    enable = true;
    openvpnPasswordFile = config.sops.secrets.gluetun-openvpn-password.path;
    openvpnUsernameFile = config.sops.secrets.gluetun-openvpn-username.path;
    webUi = {
      enable = true;
      trustProxy = true;
    };
  };

  fleet.gateway.homepage = {
    bookmarks = [
      {
        Links = [
          {
            TorrentPeek = [
              {
                href = "https://torrentpeek.net/";
                icon = "si-bittorrent";
              }
            ];
          }
          {
            GitHub = [
              {
                href = "https://github.com/";
                icon = "github.png";
              }
            ];
          }
          {
            "NixOS Search" = [
              {
                href = "https://search.nixos.org/";
                icon = "nixos.png";
              }
            ];
          }
          {
            "Homepage Docs" = [
              {
                href = "https://gethomepage.dev/";
                icon = "homepage.png";
              }
            ];
          }
          {
            "Traefik Docs" = [
              {
                href = "https://doc.traefik.io/traefik/";
                icon = "traefik.png";
              }
            ];
          }
          {
            "Technitium GitHub" = [
              {
                href = "https://github.com/TechnitiumSoftware/DnsServer";
                icon = "technitium.png";
              }
            ];
          }
        ];
      }
    ];
    customCSS = ''
      .service-description {
        white-space: pre-line;
      }
    '';
    directAddress = host.ip;
    enable = true;
    hosts = exposureCatalog.homepage.hosts;
    layout = exposureCatalog.homepage.layout ++ [
      {
        Links = {
          columns = 3;
          style = "row";
        };
      }
    ];
    linkTarget = "_blank";
    listenPort = 8082;
    openFirewall = true;
    package = homepage-dashboard_1_13_1;
    serviceGroups = exposureCatalog.homepage.serviceGroups;
  };

  fleet.gateway.netbird = {
    enable = false;
  };

  fleet.gateway.netbootxyz = {
    enable = true;
    tftpBindAddress = host.ip;
  };

  fleet.gateway.stateBackup = {
    enable = secretsEnabled;
    credentialsFile = config.sops.secrets.smb-credentials.path;
    passwordFile = config.sops.secrets.restic-password.path;
  };

  fleet.gateway.tailscale = {
    enable = true;
  };

  fleet.gateway.technitium = {
    adminPasswordFile = config.sops.secrets.technitium-admin-password.path;
    adminUsernameFile = config.sops.secrets.technitium-admin-username.path;
    enable = true;
    localZone.enable = false;
    localZones = map (zoneDomain: {
      domain = zoneDomain;
      aRecords = {
        # Gateway-routed service names resolve to Traefik through wildcard DNS.
        "*" = host.ip;
      };
    }) serviceDomains;
    package = technitium-dns-server_15_2_0;
    serverDomain = host.fqdn;
    tlsCertificateDomain = "technitium.${serviceDomain}";
    tlsSubjectAltNames = (map (zoneDomain: "DNS:technitium.${zoneDomain}") serviceDomains) ++ [
      "DNS:gateway-vm.${domain}"
      "IP:${host.ip}"
    ];
    webServiceLocalAddresses = "${host.ip},127.0.0.1,::1";
  };

  fleet.gateway.traefik = {
    accessLog.enable = true;
    dashboard.domain = "traefik.${serviceDomain}";
    dashboard.domains = map (zoneDomain: "traefik.${zoneDomain}") serviceDomains;
    dashboard.webRoute.enable = true;
    domain = serviceDomain;
    enable = true;
    metrics.enable = true;
    package = traefik_3_7_1;
    routes = exposureCatalog.traefikRoutes;
  };

  # gateway-vm skips Prometheus node-exporter but still runs the fleet
  # Checkmate/Beszel agents declared in common.nix.
  fleet.monitoring.nodeExporter.enable = lib.mkForce false;

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking.networkmanager.enable = lib.mkForce false;
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

  networking.firewall.allowedTCPPorts = [ ];

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = host.vm.disk;
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  environment.etc."fleet/gateway-exposure-smoke.tsv".text = exposureCatalog.smokeTsv;

  environment.etc."fleet/gateway-vm.md".text = ''
        gateway-vm service model
        ========================

        gateway-vm is scoped to Traefik, Homepage, Technitium, Gluetun, netboot.xyz,
        NetBird, and Tailscale. Prometheus, Grafana, Jenkins, nginx reverse proxy,
        and node exporter are intentionally not enabled on this host.

        Homelab host domain:
          *.${domain}

        Homelab service domains:
    ${lib.concatStringsSep "\n" (map (zoneDomain: "      *.${zoneDomain}") serviceDomains)}

        Declared services:
          Traefik: traefik.service, version 3.7.1, ingress ports 80 and optional 443, dashboard and metrics port 8080, JSON access logs in the service journal
          Homepage: homepage-dashboard.service, declarative service directory, LAN access on ${host.ip}:8082 and http://homepage.${serviceDomain}
          Technitium: technitium-dns-server.service, version 15.2.0, state /srv/appsdata/technitium-dns-server, admin HTTP on ${host.ip}:5380 and http://technitium.${serviceDomain}
          Gluetun: podman-gluetun.service, PIA OpenVPN container, state /srv/appsdata/gluetun, unauthenticated LAN HTTP proxy on ${host.ip}:8888, authenticated control API internal to the container namespace
          Gluetun WebUI: podman-gluetun-webui.service, LAN access through Traefik at http://gluetun.${serviceDomain}, backend only on 127.0.0.1:3000
          netboot.xyz: podman-netbootxyz.service, state /srv/appsdata/netbootxyz, web UI http://netbootxyz.${serviceDomain}, TFTP ${host.ip}:69/udp, boot file netboot.xyz.efi
          NetBird: disabled for now, state preserved at /srv/appsdata/netbird
          Tailscale: tailscaled.service, state /srv/appsdata/tailscale
          State backups: gateway-state-backup.timer, repository /mnt/backup/restic/appdata/gateway-vm

        Internal routes:
    ${exposureCatalog.routeUrlsText}

        Network boot:
          Configure the LAN DHCP server to point option 66 at ${hosts.gateway-vm.ip}
          and option 67 at netboot.xyz.efi. gateway-vm serves the netboot.xyz web
          UI, local asset server, and TFTP, but does not take over DHCP for the
          subnet.

        Guarded deploy workflow:
          nix develop
          nix flake check
          colmena build --on gateway-vm
          colmena apply --on gateway-vm dry-activate
          colmena apply --on gateway-vm switch

        Upgrade workflow for an already-running host:
          nix develop
          scripts/gateway-vm/upgrade-gateway-vm.sh run

          The upgrade wrapper verifies local tools, encrypted secrets,
          non-interactive SSH, nix flake check, and colmena build; creates a fresh
          gateway appdata backup; dry-activates the host; runs the guarded switch;
          and verifies services, listener ports, routes, DNS records, backup,
          restore validation, and tmpfiles declarations. It never restores appdata
          automatically.

        Post-deploy validation:
          systemctl is-active traefik.service
          systemctl is-active homepage-dashboard.service
          systemctl is-active technitium-dns-server.service
          systemctl is-active podman-gluetun.service
          systemctl is-active podman-gluetun-webui.service
          systemctl is-active podman-netbootxyz.service
          systemctl is-active tailscaled.service
          systemctl is-active gateway-state-backup.timer
          curl -H 'Host: gluetun.${serviceDomain}' http://127.0.0.1/api/health
          curl -H 'Host: homepage.${serviceDomain}' http://127.0.0.1/
          curl -H 'Host: homepage.h' http://127.0.0.1/
          curl -H 'Host: netbootxyz.${serviceDomain}' http://127.0.0.1/
          curl http://${host.ip}:8082/
          ss -lntu

        Recovery notes:
          Restic backs up /srv/appsdata to /mnt/backup/restic/appdata/gateway-vm
          using /run/secrets/restic-password. Gluetun and netboot.xyz store state
          directly under /srv/appsdata/gluetun and /srv/appsdata/netbootxyz;
          Technitium, NetBird, and Tailscale keep
          upstream-compatible bind mounts from /srv/appsdata/<service_name>.
          Homepage service cards and Gateway Traefik routes are generated from the
          pure Nix exposure catalog under hosts/*/exposure.nix and modules/*/catalog.nix.
          Gateway, Media, and Productivity render as four-card rows, internal HTTP
          cards use direct backend site monitors, and the bottom Links bookmark group
          renders as a three-column external reference row with icons and service names.
          Homepage has no authoritative mutable app state in this fleet pass and is
          restored by redeploying gateway-vm.

          Non-destructive validation:
            mount /mnt/backup
            systemctl start gateway-state-backup.service
            systemctl start gateway-state-restore-check.service
            systemctl status gateway-state-backup.service gateway-state-restore-check.service

          Consistency-first manual backup from the repo development shell:
            scripts/gateway-vm/create-gateway-backup.sh

            The script stops gateway-state-backup.timer, stops active stateful
            Gateway services, runs the Restic backup and restore validation, lists
            recent snapshots, restarts services and the timer, then runs Gateway
            service validation.

          Restore outline:
            1. Deploy gateway-vm once to create users, secrets, mounts, and units.
            2. Stop Technitium, Gluetun, netboot.xyz, NetBird, and Tailscale before replacing state.
            3. Mount /mnt/backup.
            4. Choose a gateway-vm/appsdata snapshot ID.
            5. Restore the snapshot to / with restic --verify.
            6. Run systemd-tmpfiles --create.
            7. Restart homepage-dashboard.service, technitium-dns-server.service, podman-gluetun.service, podman-gluetun-webui.service, podman-netbootxyz.service, netbird.service, and tailscaled.service.

          Keep auth keys in encrypted secrets only; do not write them into Nix
          files, generated configs, recovery notes, logs, or chat.
  '';

  time.timeZone = host.timezone;
  system.stateVersion = "25.11";
}
