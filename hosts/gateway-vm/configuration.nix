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
  serviceDomain = "h";
  secretsFile = ../../secrets/secrets.yaml;
  secretsEnabled = builtins.pathExists secretsFile;
  technitium-dns-server-library_15_2_0 = pkgs.callPackage ../../modules/gateway/technitium/library-package.nix { };
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
    host = "homepage.${serviceDomain}";
    layout = [
      {
        Gateway = {
          columns = 4;
          style = "row";
        };
      }
      {
        Media = {
          columns = 4;
          style = "row";
        };
      }
      {
        Productivity = {
          columns = 4;
          style = "row";
        };
      }
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
    serviceGroups = [
      {
        name = "Gateway";
        services = [
          {
            name = "Homepage";
            description = "http://${host.ip}:8082";
            href = "http://homepage.${serviceDomain}/";
            icon = "homepage.png";
            siteMonitor = "http://127.0.0.1:8082/";
          }
          {
            name = "Traefik";
            description = "http://${host.ip}:8080/dashboard/";
            href = "http://traefik.${serviceDomain}/dashboard/";
            icon = "traefik.png";
            siteMonitor = "http://127.0.0.1:8080/dashboard/";
          }
          {
            name = "Technitium";
            description = "http://${host.ip}:5380";
            href = "http://technitium.${serviceDomain}/";
            icon = "technitium.png";
            siteMonitor = "http://127.0.0.1:5380/";
          }
          {
            name = "Gluetun";
            description = "HTTP proxy: gateway.vm.home.arpa:8888\mSOCKS v5 Host: gateway.vm.home.arpa:8388";
            href = "http://gluetun.${serviceDomain}/";
            icon = "gluetun.png";
            siteMonitor = "http://127.0.0.1:3000/api/health";
          }
          {
            name = "Netboot.xyz";
            description = "PXE boot menu and local asset manager\nTFTP ${host.ip}:69/udp";
            href = "http://netbootxyz.${serviceDomain}/";
            icon = "netboot.png";
            siteMonitor = "http://127.0.0.1:3001/";
          }
          {
            name = "Traefik Dashboard IP";
            description = "http://${host.ip}:8080/metrics";
            href = "http://${host.ip}:8080/dashboard/";
            icon = "traefik.png";
            siteMonitor = "http://${host.ip}:8080/dashboard/";
          }
          {
            name = "Technitium Direct IP";
            description = "http://technitium.${serviceDomain}/";
            href = "http://${host.ip}:5380/";
            icon = "technitium.png";
            siteMonitor = "http://${host.ip}:5380/";
          }
        ];
      }
      {
        name = "Media";
        services = [
          {
            name = "Jellyfin";
            description = "http://${hosts.media-vm.ip}:8096";
            href = "http://jellyfin.${serviceDomain}/";
            icon = "jellyfin.png";
            siteMonitor = "http://${hosts.media-vm.ip}:8096/";
          }
          {
            name = "Audiobookshelf";
            description = "http://${hosts.media-vm.ip}:8000";
            href = "http://audiobookshelf.${serviceDomain}/";
            icon = "audiobookshelf.png";
            siteMonitor = "http://${hosts.media-vm.ip}:8000/";
          }
          {
            name = "Kavita";
            description = "http://${hosts.media-vm.ip}:5000";
            href = "http://kavita.${serviceDomain}/";
            icon = "kavita.png";
            siteMonitor = "http://${hosts.media-vm.ip}:5000/";
          }
          {
            name = "Sonarr";
            description = "http://${hosts.media-vm.ip}:8989";
            href = "http://sonarr.${serviceDomain}/";
            icon = "sonarr.png";
            siteMonitor = "http://${hosts.media-vm.ip}:8989/";
          }
          {
            name = "Radarr";
            description = "http://${hosts.media-vm.ip}:7878";
            href = "http://radarr.${serviceDomain}/";
            icon = "radarr.png";
            siteMonitor = "http://${hosts.media-vm.ip}:7878/";
          }
          {
            name = "Prowlarr";
            description = "http://${hosts.media-vm.ip}:9696";
            href = "http://prowlarr.${serviceDomain}/";
            icon = "prowlarr.png";
            siteMonitor = "http://${hosts.media-vm.ip}:9696/";
          }
          {
            name = "Bazarr";
            description = "Subtitles http://${hosts.media-vm.ip}:6767";
            href = "http://bazarr.${serviceDomain}/";
            icon = "bazarr.png";
            siteMonitor = "http://${hosts.media-vm.ip}:6767/";
          }
          {
            name = "qBittorrent";
            description = "http://${hosts.media-vm.ip}:8080";
            href = "http://qbittorrent.${serviceDomain}/";
            icon = "qbittorrent.png";
            siteMonitor = "http://${hosts.media-vm.ip}:8080/";
          }
          {
            name = "Media Gluetun";
            description = "media VPN @ http://${hosts.media-vm.ip}:3001";
            href = "http://media-gluetun.${serviceDomain}/";
            icon = "gluetun.png";
            siteMonitor = "http://${hosts.media-vm.ip}:3001/api/health";
          }
          {
            name = "SABnzbd";
            description = "http://${hosts.media-vm.ip}:8085";
            href = "http://sabnzbd.${serviceDomain}/";
            icon = "sabnzbd.png";
            siteMonitor = "http://${hosts.media-vm.ip}:8085/";
          }
          {
            name = "Seerr";
            description = "http://${hosts.media-vm.ip}:5055";
            href = "http://seerr.${serviceDomain}/";
            icon = "seerr.png";
            siteMonitor = "http://${hosts.media-vm.ip}:5055/";
          }
        ];
      }
      {
        name = "Productivity";
        services = [
          {
            name = "Gitea";
            description = "Git repositories\nhttp://${hosts.productivity-vm.ip}:3000";
            href = "http://gitea.${serviceDomain}/";
            icon = "gitea.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:3000/";
          }
          {
            name = "Forgejo";
            description = "Gitea community forge\nhttp://${hosts.productivity-vm.ip}:3002";
            href = "http://forgejo.${serviceDomain}/";
            icon = "forgejo.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:3002/";
          }
          {
            name = "Docs";
            description = "Material for MkDocs\nhttp://${hosts.productivity-vm.ip}:80";
            href = "http://docs.${serviceDomain}/";
            icon = "mkdocs.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}/";
          }
          {
            name = "Paperless";
            description = "Document OCR and archive\nhttp://${hosts.productivity-vm.ip}:80";
            href = "http://paperless.${serviceDomain}/";
            icon = "paperless-ngx.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}/";
          }
          {
            name = "FreshRSS";
            description = "RSS reader\nhttp://${hosts.productivity-vm.ip}:80";
            href = "http://freshrss.${serviceDomain}/";
            icon = "freshrss.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}/";
          }
          {
            name = "SearXNG";
            description = "Private metasearch\nhttp://${hosts.productivity-vm.ip}:8087";
            href = "http://searxng.${serviceDomain}/";
            icon = "searxng.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:8087/";
          }
          {
            name = "PrivateBin";
            description = "Encrypted temporary text sharing\nhttp://${hosts.productivity-vm.ip}:80";
            href = "http://privatebin.${serviceDomain}/";
            icon = "privatebin.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}/";
          }
          {
            name = "Vaultwarden";
            description = "Password vault\nhttp://${hosts.productivity-vm.ip}:8222";
            href = "http://vaultwarden.${serviceDomain}/";
            icon = "vaultwarden.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:8222/";
          }
          {
            name = "Syncthing";
            description = "File synchronization\nhttp://${hosts.productivity-vm.ip}:8384";
            href = "http://syncthing.${serviceDomain}/";
            icon = "syncthing.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:8384/";
          }
          {
            name = "Stirling PDF";
            description = "PDF toolkit\nhttp://${hosts.productivity-vm.ip}:8086";
            href = "http://stirling-pdf.${serviceDomain}/";
            icon = "stirling-pdf.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:8086/";
          }
          {
            name = "Firefly III";
            description = "Personal finance\nhttp://${hosts.productivity-vm.ip}:80";
            href = "http://firefly.${serviceDomain}/";
            icon = "firefly-iii.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}/";
          }
          {
            name = "Nextcloud";
            description = "Private cloud files\nhttp://${hosts.productivity-vm.ip}:80";
            href = "http://nextcloud.${serviceDomain}/";
            icon = "nextcloud.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}/";
          }
          {
            name = "Shlink";
            description = "Short-link web client\nhttp://${hosts.productivity-vm.ip}:8089";
            href = "http://shlink.${serviceDomain}/";
            icon = "shlink.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:8089/";
          }
          {
            name = "Garage";
            description = "Static website endpoint\nhttp://${hosts.productivity-vm.ip}:3902";
            href = "http://garage-web.${serviceDomain}/";
            icon = "garage.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:3902/";
          }
          {
            name = "RustFS";
            description = "S3-compatible object storage\nhttp://${hosts.productivity-vm.ip}:9000";
            href = "http://rustfs.${serviceDomain}/";
            icon = "rustfs.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:9000/health";
          }
          {
            name = "RustFS Console";
            description = "Object storage console\nhttp://${hosts.productivity-vm.ip}:9001";
            href = "http://rustfs-console.${serviceDomain}/";
            icon = "rustfs.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:9001/rustfs/console/health";
          }
          {
            name = "ntfy";
            description = "Push notifications\nhttp://${hosts.productivity-vm.ip}:2586";
            href = "http://ntfy.${serviceDomain}/";
            icon = "ntfy.png";
            siteMonitor = "http://${hosts.productivity-vm.ip}:2586/v1/health";
          }
        ];
      }
    ];
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
    localZone.domain = serviceDomain;
    localZone.aRecords = {
      # Gateway-routed service names resolve to Traefik through wildcard DNS.
      "*" = host.ip;
    };
    package = technitium-dns-server_15_2_0;
    serverDomain = host.fqdn;
    tlsCertificateDomain = "technitium.${serviceDomain}";
    tlsSubjectAltNames = [
      "DNS:technitium.${serviceDomain}"
      "DNS:gateway-vm.${domain}"
      "IP:${host.ip}"
    ];
    webServiceLocalAddresses = "${host.ip},127.0.0.1,::1";
  };

  fleet.gateway.traefik = {
    accessLog.enable = true;
    dashboard.domain = "traefik.${serviceDomain}";
    dashboard.webRoute.enable = true;
    domain = serviceDomain;
    enable = true;
    metrics.enable = true;
    package = traefik_3_7_1;
    routes = {
      audiobookshelf = {
        description = "Audiobookshelf media library";
        host = "audiobookshelf.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:8000";
      };
      bazarr = {
        description = "Bazarr subtitle management";
        host = "bazarr.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:6767";
      };
      jellyfin = {
        description = "Jellyfin media server";
        host = "jellyfin.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:8096";
      };
      seerr = {
        description = "Seerr requests";
        host = "seerr.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:5055";
      };
      gluetun = {
        description = "Gluetun WebUI";
        host = "gluetun.${serviceDomain}";
        url = "http://127.0.0.1:3000";
      };
      homepage = {
        description = "Homepage service directory";
        host = "homepage.${serviceDomain}";
        url = "http://127.0.0.1:8082";
      };
      docs = {
        description = "Material for MkDocs knowledge base";
        host = "docs.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:80";
      };
      firefly = {
        description = "Firefly III personal finance";
        host = "firefly.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:80";
      };
      freshrss = {
        description = "FreshRSS reader";
        host = "freshrss.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:80";
      };
      forgejo = {
        description = "Forgejo software forge";
        host = "forgejo.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:3002";
      };
      garage = {
        description = "Garage standalone S3 API";
        host = "garage.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:3900";
      };
      garage-web = {
        description = "Garage static website endpoint";
        host = "garage-web.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:3902";
      };
      gitea = {
        description = "Gitea Git repositories";
        host = "gitea.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:3000";
      };
      netbootxyz = {
        description = "netboot.xyz web configuration UI";
        host = "netbootxyz.${serviceDomain}";
        url = "http://127.0.0.1:3001";
      };
      nextcloud = {
        description = "Nextcloud private cloud files";
        host = "nextcloud.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:80";
      };
      ntfy = {
        description = "ntfy push notifications";
        host = "ntfy.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:2586";
      };
      paperless = {
        description = "Paperless-ngx document archive";
        host = "paperless.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:80";
      };
      privatebin = {
        description = "PrivateBin temporary text sharing";
        host = "privatebin.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:80";
      };
      kavita = {
        description = "Kavita library";
        host = "kavita.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:5000";
      };
      prowlarr = {
        description = "Prowlarr indexer management";
        host = "prowlarr.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:9696";
      };
      qbittorrent = {
        description = "qBittorrent downloads";
        host = "qbittorrent.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:8080";
      };
      media-gluetun = {
        description = "MediaVM Gluetun WebUI for download clients";
        host = "media-gluetun.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:3001";
      };
      radarr = {
        description = "Radarr movie management";
        host = "radarr.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:7878";
      };
      rustfs = {
        description = "RustFS S3-compatible object storage";
        host = "rustfs.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:9000";
      };
      rustfs-console = {
        description = "RustFS object storage console";
        host = "rustfs-console.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:9001";
      };
      sabnzbd = {
        description = "SABnzbd downloads";
        host = "sabnzbd.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:8085";
      };
      searxng = {
        description = "SearXNG private metasearch";
        host = "searxng.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:8087";
      };
      shlink = {
        description = "Shlink short-link API and redirect service";
        host = "s.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:8088";
      };
      shlink-web = {
        description = "Shlink Web Client";
        host = "shlink.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:8089";
      };
      sonarr = {
        description = "Sonarr TV management";
        host = "sonarr.${serviceDomain}";
        url = "http://${hosts.media-vm.ip}:8989";
      };
      stirling-pdf = {
        description = "Stirling PDF toolkit";
        host = "stirling-pdf.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:8086";
      };
      syncthing = {
        description = "Syncthing file synchronization";
        host = "syncthing.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:8384";
      };
      technitium = {
        description = "Technitium DNS administration and DoH endpoint";
        host = "technitium.${serviceDomain}";
        url = "http://127.0.0.1:5380";
      };
      vaultwarden = {
        description = "Vaultwarden password vault";
        host = "vaultwarden.${serviceDomain}";
        url = "http://${hosts.productivity-vm.ip}:8222";
      };
    };
  };

  # common.nix enables node-exporter by default; gateway-vm intentionally does
  # not run monitoring services.
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

  environment.etc."fleet/gateway-vm.md".text = ''
    gateway-vm service model
    ========================

    gateway-vm is scoped to Traefik, Homepage, Technitium, Gluetun, netboot.xyz,
    NetBird, and Tailscale. Prometheus, Grafana, Jenkins, nginx reverse proxy,
    and node exporter are intentionally not enabled on this host.

    Homelab host domain:
      *.${domain}

    Homelab service domain:
      *.${serviceDomain}

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
      http://traefik.${serviceDomain}/dashboard/
      http://traefik.${serviceDomain}:8080/dashboard/
      http://traefik.${serviceDomain}:8080/metrics
      http://homepage.${serviceDomain}
      http://netbootxyz.${serviceDomain}
      http://technitium.${serviceDomain}
      http://gluetun.${serviceDomain}
      http://jellyfin.${serviceDomain}
      http://audiobookshelf.${serviceDomain}
      http://kavita.${serviceDomain}
      http://sonarr.${serviceDomain}
      http://radarr.${serviceDomain}
      http://prowlarr.${serviceDomain}
      http://bazarr.${serviceDomain}
      http://qbittorrent.${serviceDomain}
      http://media-gluetun.${serviceDomain}
      http://sabnzbd.${serviceDomain}
      http://seerr.${serviceDomain}
      http://gitea.${serviceDomain}
      http://forgejo.${serviceDomain}
      http://docs.${serviceDomain}
      http://paperless.${serviceDomain}
      http://freshrss.${serviceDomain}
      http://searxng.${serviceDomain}
      http://privatebin.${serviceDomain}
      http://vaultwarden.${serviceDomain}
      http://syncthing.${serviceDomain}
      http://stirling-pdf.${serviceDomain}
      http://firefly.${serviceDomain}
      http://nextcloud.${serviceDomain}
      http://s.${serviceDomain}
      http://shlink.${serviceDomain}
      http://garage.${serviceDomain}
      http://garage-web.${serviceDomain}
      http://rustfs.${serviceDomain}
      http://rustfs-console.${serviceDomain}
      http://ntfy.${serviceDomain}

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
      curl -H 'Host: netbootxyz.${serviceDomain}' http://127.0.0.1/
      curl http://${host.ip}:8082/
      ss -lntu

    Recovery notes:
      Restic backs up /srv/appsdata to /mnt/backup/restic/appdata/gateway-vm
      using /run/secrets/restic-password. Gluetun and netboot.xyz store state
      directly under /srv/appsdata/gluetun and /srv/appsdata/netbootxyz;
      Technitium, NetBird, and Tailscale keep
      upstream-compatible bind mounts from /srv/appsdata/<service_name>.
      Homepage service cards are generated from Nix under /etc/homepage-dashboard;
      Gateway, Media, and Productivity render as four-card rows, internal HTTP
      cards use direct backend site monitors, and the bottom Links bookmark group
      renders as a three-column external reference row with icons and service names.
      it has no authoritative mutable app state in this fleet pass and is restored
      by redeploying gateway-vm.

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
