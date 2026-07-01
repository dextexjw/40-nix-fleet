{
  config,
  fleetHostName ? "gateway-vm",
  lib,
  pkgs,
  ...
}:

let
  hosts = import ../../hosts.nix;
  gatewayCluster = import ../../lib/gateway-cluster.nix { inherit hosts; };
  hostName = fleetHostName;
  host = hosts.${hostName};
  domain = host.domain;
  gatewayScriptDir = hostName;
  gatewayClientAddress = gatewayCluster.clientAddress;
  gatewayPriority = if hostName == gatewayCluster.primary then 150 else 100;
  serviceDomains = (import ../../lib/service-domains.nix).all;
  serviceDomain = builtins.head serviceDomains;
  exposure = import ../../lib/exposure.nix {
    inherit lib;
    root = ../..;
  };
  exposureCatalog = exposure.load {
    gatewayHost = host;
    dnsExpectedAddress = gatewayClientAddress;
    inherit hosts serviceDomain serviceDomains;
  };
  exposureDnsHosts = lib.unique (
    lib.concatMap (
      service:
      let
        route = service.route or null;
        smoke = service.smoke or { };
      in
      if smoke ? dnsHosts then
        smoke.dnsHosts
      else if (smoke.dns or (route != null)) && route != null then
        route.hosts
      else
        [ ]
    ) exposureCatalog.serviceEntries
  );
  zoneRecordName =
    zoneDomain: dnsHost:
    let
      zoneSuffix = ".${zoneDomain}";
    in
    if dnsHost == zoneDomain then
      "@"
    else if lib.hasSuffix zoneSuffix dnsHost then
      lib.removeSuffix zoneSuffix dnsHost
    else
      null;
  zoneARecords =
    zoneDomain:
    lib.listToAttrs (
      map (name: lib.nameValuePair name gatewayClientAddress) (
        lib.unique (
          builtins.filter (name: name != null) ([ "*" ] ++ map (zoneRecordName zoneDomain) exposureDnsHosts)
        )
      )
    );
  authentikOidcApplications = builtins.filter (
    app: app.mode == "native-oidc" && app.oidc ? clientSecretFile
  ) exposureCatalog.authentikApplications;
  authentikProvisionSecret = {
    owner = "authentik";
    group = "authentik";
    mode = "0400";
    restartUnits = [ "authentik-provision.service" ];
  };
  authentikOidcSecrets = lib.listToAttrs (
    map (
      app:
      lib.nameValuePair (builtins.baseNameOf (toString app.oidc.clientSecretFile)) authentikProvisionSecret
    ) authentikOidcApplications
  );
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
    ../../modules/gateway/gluetun.nix
    ../../modules/gateway/authentik.nix
    ../../modules/gateway/homepage.nix
    ../../modules/gateway/keepalived.nix
    ../../modules/gateway/netbird.nix
    ../../modules/gateway/state-backup.nix
    ../../modules/gateway/tailscale.nix
    ../../modules/gateway/technitium
    ../../modules/gateway/traefik.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  fleet.host.name = hostName;
  users.motd = "${hostName}: Authentik SSO, Traefik ingress, Homepage, Technitium DNS, Gluetun VPN proxy, NetBird, and Tailscale";

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
      authentik-bootstrap-email = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [
          "authentik-provision.service"
          "authentik-server.service"
          "authentik-worker.service"
        ];
      };
      authentik-bootstrap-password = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [
          "authentik-provision.service"
          "authentik-worker.service"
        ];
      };
      authentik-bootstrap-token = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [
          "authentik-provision.service"
          "authentik-worker.service"
        ];
      };
      authentik-bootstrap-username = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [
          "authentik-provision.service"
          "authentik-server.service"
          "authentik-worker.service"
        ];
      };
      authentik-postgresql-password = {
        owner = "postgres";
        group = "authentik";
        mode = "0440";
        restartUnits = [
          "authentik-postgresql-password.service"
          "authentik-server.service"
          "authentik-worker.service"
        ];
      };
      authentik-secret-key = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [
          "authentik-server.service"
          "authentik-worker.service"
        ];
      };
    }
    // authentikOidcSecrets
    // {
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
      traefik-cloudflare-dns-api-token = {
        owner = "traefik";
        group = "traefik";
        restartUnits = [ "traefik.service" ];
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

  fleet.gateway.authentik = {
    aliases = [ "auth.h" ];
    applications = exposureCatalog.authentikApplications;
    bootstrap = {
      emailFile = config.sops.secrets.authentik-bootstrap-email.path;
      passwordFile = config.sops.secrets.authentik-bootstrap-password.path;
      tokenFile = config.sops.secrets.authentik-bootstrap-token.path;
      usernameFile = config.sops.secrets.authentik-bootstrap-username.path;
    };
    domain = "auth.jax22.com";
    enable = true;
    postgresql.passwordFile = config.sops.secrets.authentik-postgresql-password.path;
    runtime = {
      httpTimeout = 90;
      webThreads = 2;
      webWorkers = 2;
      workerProcesses = 1;
      workerThreads = 1;
    };
    secretKeyFile = config.sops.secrets.authentik-secret-key.path;
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
    directAddresses = lib.optionals (gatewayCluster.vip != null) [
      gatewayClientAddress
    ];
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

  fleet.gateway.keepalived = {
    enable = gatewayCluster.vip != null;
    hostAddress = host.ip;
    interface = "ens18";
    peerAddresses = gatewayCluster.addresses;
    priority = gatewayPriority;
    vip = gatewayClientAddress;
    virtualRouterId = 102;
  };

  fleet.gateway.netbird = {
    enable = false;
  };

  fleet.gateway.stateBackup = {
    enable = secretsEnabled;
    credentialsFile = config.sops.secrets.smb-credentials.path;
    hostName = hostName;
    passwordFile = config.sops.secrets.restic-password.path;
    repository = "/mnt/backup/restic/appdata/${hostName}";
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
      # Keep wildcard coverage for new routes, and converge explicit records so
      # older host-specific entries do not override the shared Gateway VIP.
      aRecords = zoneARecords zoneDomain;
    }) serviceDomains;
    package = technitium-dns-server_15_2_0;
    serverDomain = host.fqdn;
    tlsCertificateDomain = "technitium.${serviceDomain}";
    tlsSubjectAltNames = (map (zoneDomain: "DNS:technitium.${zoneDomain}") serviceDomains) ++ [
      "DNS:${hostName}.${domain}"
      "IP:${host.ip}"
      "IP:${gatewayClientAddress}"
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
    authentik.enable = true;
    metrics.enable = true;
    package = traefik_3_7_1;
    routes = exposureCatalog.traefikRoutes;
    tcpRoutes = exposureCatalog.traefikTcpRoutes;
    tls = {
      enable = true;
      domain = "jax22.com";
      extraSans = [
        "*.gateway.jax22.com"
        "*.media.jax22.com"
        "s3.garage.jax22.com"
        "s3.rustfs.jax22.com"
      ];
      resolver = "letsencrypt";
      acme = {
        dnsApiTokenFile = config.sops.secrets.traefik-cloudflare-dns-api-token.path;
        dnsProvider = "cloudflare";
        dnsResolvers = [
          "1.1.1.1:53"
          "8.8.8.8:53"
        ];
        email = "admin@jax22.com";
        storage = "/var/lib/traefik/acme.json";
      };
    };
    udpRoutes = exposureCatalog.traefikUdpRoutes;
  };

  # Gateway nodes skip Prometheus node-exporter but still run the fleet
  # Checkmate/Beszel agents declared in common.nix.
  fleet.monitoring.nodeExporter.enable = lib.mkForce false;

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNS = [
        "1.1.1.1"
        "8.8.8.8"
        "9.9.9.9"
      ];
      FallbackDNS = [
        "1.0.0.1"
        "8.8.4.4"
        "149.112.112.112"
      ];
    };
  };

  # Keep the LAN resolver scoped to home.arpa so Gateway deploys do not depend
  # on 10.2.20.1 for public names such as cache.nixos.org.
  systemd.network.networks."10-lan".networkConfig.DNSDefaultRoute = lib.mkForce false;

  networking.firewall.allowedTCPPorts = [ ];

  # ============================================================================
  # SYSTEM
  # ============================================================================

  environment.etc."fleet/gateway-exposure-smoke.tsv".text = exposureCatalog.smokeTsv;

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  environment.etc."fleet/${hostName}.md".text = ''
        ${hostName} service model
        ========================

        ${hostName} is scoped to Authentik SSO, Traefik, Homepage, Technitium, Gluetun,
        NetBird, and Tailscale. Prometheus, Grafana, Jenkins, nginx reverse proxy,
        and node exporter are intentionally not enabled on this host.

        Homelab host domain:
          *.${domain}

        Homelab service domains:
    ${lib.concatStringsSep "\n" (map (zoneDomain: "      *.${zoneDomain}") serviceDomains)}

        Declared services:
          Authentik: authentik-server.service and authentik-worker.service, version ${pkgs.authentik.version}, state /srv/appsdata/authentik, PostgreSQL data /srv/appsdata/authentik/postgresql, Redis data /srv/appsdata/authentik/redis, canonical URL https://auth.jax22.com, LAN alias http://auth.h, backend only on 127.0.0.1:9000, metrics on 127.0.0.1:9300
          Traefik: traefik.service, version 3.7.1, HTTP ingress port 80, HTTPS ingress port 443 for jax22.com routes using Let's Encrypt DNS-01, ACME state /srv/appsdata/traefik/acme.json, dashboard and metrics port 8080, JSON access logs in the service journal
          Homepage: homepage-dashboard.service, declarative service directory, LAN access on ${host.ip}:8082, https://homepage.jax22.com, and http://homepage.h
          Technitium: technitium-dns-server.service, version 15.2.0, state /srv/appsdata/technitium-dns-server, admin HTTP on ${host.ip}:5380, https://technitium.jax22.com, and http://technitium.h
          Gluetun: podman-gluetun.service, PIA OpenVPN container, state /srv/appsdata/gluetun, unauthenticated LAN HTTP proxy on ${host.ip}:8888, authenticated control API internal to the container namespace
          Gluetun WebUI: podman-gluetun-webui.service, LAN access through Traefik at https://gluetun.gateway.jax22.com and http://gluetun.gateway.h, backend only on 127.0.0.1:3000
          Keepalived: keepalived.service, unicast VRRP on ${host.ip}, shared client VIP ${gatewayClientAddress}, preferred primary ${gatewayCluster.primary}
          netboot.xyz route: Gateway Traefik routes https://netbootxyz.jax22.com and http://netbootxyz.h to productivity-vm at ${hosts.productivity-vm.ip}:3001; direct assets and TFTP live on productivity-vm
          NetBird: disabled for now, state preserved at /srv/appsdata/netbird
          Tailscale: tailscaled.service, state /srv/appsdata/tailscale
          State backups: gateway-state-backup.timer, repository /mnt/backup/restic/appdata/${hostName}

        Resolver model:
          systemd-resolved uses public recursive DNS for ordinary internet names. The LAN resolver 10.2.20.1 remains route-only for home.arpa so NAS and VM hostnames still resolve, but public names such as cache.nixos.org do not depend on the LAN resolver during Colmena deploys. Gateway service-zone records resolve to the shared VIP ${gatewayClientAddress}; query ${host.ip} directly only for node-local diagnostics.

        Auth model:
          Authentik is the fleet identity provider. Browser routes are ordinary Traefik routes unless the application has its own auth, a native SSO integration, or an explicitly declared forward-auth proxy route. The On-Demand Apps Dashboard at https://ondemand.jax22.com is protected with Authentik forward-auth for productivity-users; ordinary app routes still prefer native OIDC.
          Native OIDC and forward-auth applications are declared in the exposure catalog. Beszel uses the beszel client with monitoring-users. BookOrbit uses the bookorbit client with media-users and https://bookorbit.jax22.com/oauth2-callback; the BookOrbit app-side provider and coldkey local account are declared on media-vm by bookorbit-declarative-config.service. Memos uses the memos client with productivity-users and https://memos.jax22.com/auth/callback. Gitea uses the gitea client with productivity-users and https://gitea.jax22.com/user/oauth2/authentik/callback. Forgejo uses the forgejo client with productivity-users and https://forgejo.jax22.com/user/oauth2/authentik/callback. Paperless uses the paperless client with productivity-users and https://paperless.jax22.com/accounts/oidc/authentik/login/callback/. Nextcloud uses the nextcloud client with productivity-users and https://nextcloud.jax22.com/apps/user_oidc/code. RustFS Console uses the rustfs-console client with fleet-admins and https://rustfs.jax22.com/rustfs/admin/v3/oidc/callback/authentik.

        Internal routes:
    ${exposureCatalog.routeUrlsText}

        Network boot:
          Configure the LAN DHCP server to point option 66 at ${hosts.productivity-vm.ip}
          and option 67 at netboot.xyz.efi. productivity-vm serves the
          netboot.xyz local asset server and TFTP. ${hostName} only routes the
          browser UI and does not take over DHCP for the subnet.

        Guarded deploy workflow:
          nix develop
          nix flake check
          colmena build --on ${hostName}
          colmena apply --on ${hostName} dry-activate
          colmena apply --on ${hostName} switch

        Upgrade workflow for an already-running host:
          nix develop
          scripts/${gatewayScriptDir}/upgrade-${hostName}.sh run

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
          systemctl is-active tailscaled.service
          systemctl is-active keepalived.service
          systemctl is-active gateway-state-backup.timer
          curl --resolve homepage.jax22.com:443:127.0.0.1 https://homepage.jax22.com/
          curl --resolve traefik.jax22.com:443:127.0.0.1 https://traefik.jax22.com/dashboard/
          curl -H 'Host: gluetun.gateway.${serviceDomain}' http://127.0.0.1/api/health
          curl -H 'Host: homepage.${serviceDomain}' http://127.0.0.1/
          curl -H 'Host: homepage.h' http://127.0.0.1/
          curl -H 'Host: netbootxyz.${serviceDomain}' http://127.0.0.1/
          curl http://${host.ip}:8082/
          ip -o addr show ${config.fleet.gateway.keepalived.interface} | grep -F '${gatewayClientAddress}/24'
          stat -c '%U:%G %a' /var/lib/traefik/acme.json
          ss -lntu

        Recovery notes:
          Restic backs up /srv/appsdata to /mnt/backup/restic/appdata/${hostName}
          using /run/secrets/restic-password. Authentik and Gluetun store state
          directly under /srv/appsdata/authentik and /srv/appsdata/gluetun;
          Technitium, Traefik, NetBird, and Tailscale keep
          upstream-compatible bind mounts from /srv/appsdata/<service_name>.
          Traefik's ACME account and wildcard certificate state is kept in
          /srv/appsdata/traefik/acme.json and should remain owned by traefik:traefik
          with mode 0600.
          Homepage service cards and Gateway Traefik routes are generated from the
          pure Nix exposure catalog under hosts/*/exposure.nix and modules/*/catalog.nix.
          Gateway, Media, and Productivity render as four-card rows, internal HTTP
          cards use direct backend site monitors, and the bottom Links bookmark group
          renders as a three-column external reference row with icons and service names.
          Homepage has no authoritative mutable app state in this fleet pass and is
          restored by redeploying ${hostName}.

          Non-destructive validation:
            mount /mnt/backup
            systemctl start gateway-state-backup.service
            systemctl start gateway-state-restore-check.service
            systemctl status gateway-state-backup.service gateway-state-restore-check.service

          Consistency-first manual backup from the repo development shell:
            scripts/${gatewayScriptDir}/create-${
              if hostName == "gateway-vm" then "gateway" else "gateway2"
            }-backup.sh

            The script stops gateway-state-backup.timer, stops active stateful
            Gateway services, runs the Restic backup and restore validation, lists
            recent snapshots, restarts services and the timer, then runs Gateway
            service validation.

          Restore outline:
            1. Deploy ${hostName} once to create users, secrets, mounts, and units.
            2. Stop Traefik, Authentik, PostgreSQL, Redis, Technitium, Gluetun, NetBird, and Tailscale before replacing state.
            3. Mount /mnt/backup.
            4. Choose a ${hostName}/appsdata snapshot ID.
            5. Restore the snapshot to / with restic --verify.
            6. Run systemd-tmpfiles --create.
            7. Restart postgresql.service, redis-authentik.service, authentik-server.service, authentik-worker.service, traefik.service, homepage-dashboard.service, technitium-dns-server.service, podman-gluetun.service, podman-gluetun-webui.service, netbird.service, and tailscaled.service.

          Keep auth keys, DNS API tokens, and service secrets in encrypted secrets only; do not write them into Nix
          files, generated configs, recovery notes, logs, or chat.
  '';
}
