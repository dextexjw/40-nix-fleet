{
  host,
  serviceDomain ? "h",
  serviceDomains ? [ serviceDomain ],
}:

let
  backend = port: "http://${host.ip}:${toString port}";
  hostnames = name: map (domain: "${name}.${domain}") serviceDomains;
  monitorBase = port: if port == 80 then "http://${host.ip}" else backend port;
  urlScheme = hostName: if builtins.match ".*[.]h" hostName != null then "http" else "https";
  publicHostUrl = hostName: path: "${urlScheme hostName}://${hostName}${path}";
  publicServiceUrl = hostPrefix: publicHostUrl (builtins.head (hostnames hostPrefix));

  mkService =
    {
      id,
      name,
      port,
      routeDescription,
      icon,
      homepageDescription,
      hostPrefix ? id,
      hostNames ? hostnames hostPrefix,
      homepageHref ? null,
      homepageEnableSiteMonitor ? true,
      homepageSiteMonitor ? null,
      monitorPath ? "/",
      rootRedirectPath ? null,
      smokeHttp ? null,
      checkmate ? { },
      authMode ? "none",
      authGroups ? [ ],
      authOidc ? { },
    }:
    let
      primaryHostName = builtins.head hostNames;
    in
    {
      inherit id name;
      route = {
        description = routeDescription;
        hosts = hostNames;
        inherit rootRedirectPath;
        url = backend port;
      };
      homepage = {
        description = homepageDescription;
        href =
          if homepageHref == null then "${urlScheme primaryHostName}://${primaryHostName}/" else homepageHref;
        inherit icon;
      }
      // (
        if homepageEnableSiteMonitor then
          {
            siteMonitor =
              if homepageSiteMonitor == null then "${monitorBase port}${monitorPath}" else homepageSiteMonitor;
          }
        else
          { }
      );
    }
    // (
      if authMode == "none" then
        { }
      else
        {
          auth = {
            mode = authMode;
            groups = authGroups;
            oidc = authOidc;
          };
        }
    )
    // (
      if smokeHttp == null then
        { }
      else
        {
          smoke.http = smokeHttp;
        }
    )
    // (
      if checkmate == { } then
        { }
      else
        {
          inherit checkmate;
        }
    );

  mkRouteOnly =
    {
      id,
      name,
      port,
      routeDescription,
      hostPrefix ? id,
      hostNames ? hostnames hostPrefix,
      rootRedirectPath ? null,
      smokeHttp ? null,
      checkmate ? { },
      authMode ? "none",
      authGroups ? [ ],
      authOidc ? { },
    }:
    {
      inherit id name;
      route = {
        description = routeDescription;
        hosts = hostNames;
        inherit rootRedirectPath;
        url = backend port;
      };
    }
    // (
      if authMode == "none" then
        { }
      else
        {
          auth = {
            mode = authMode;
            groups = authGroups;
            oidc = authOidc;
          };
        }
    )
    // (
      if smokeHttp == null then
        { }
      else
        {
          smoke.http = smokeHttp;
        }
    )
    // (
      if checkmate == { } then
        { }
      else
        {
          inherit checkmate;
        }
    );
in
{
  groups = [
    {
      name = "Productivity";
      order = 30;
      columns = 4;
      style = "row";
      services = [
        (mkService {
          id = "memos";
          name = "Memos";
          port = 5230;
          routeDescription = "Memos personal notes";
          icon = "memos.png";
          homepageDescription = "Personal notes\n${backend 5230}";
          authMode = "native-oidc";
          authGroups = [ "productivity-users" ];
          authOidc = {
            clientId = "memos";
            clientSecretFile = "/run/secrets/memos-oidc-client-secret";
            launchUrl = "https://memos.jax22.com/";
            redirectUris = [ "https://memos.jax22.com/auth/callback" ];
          };
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "paperless";
          name = "Paperless";
          port = 80;
          routeDescription = "Paperless-ngx document archive";
          icon = "paperless-ngx.png";
          homepageDescription = "Document OCR and archive\n${backend 80}";
          authMode = "native-oidc";
          authGroups = [ "productivity-users" ];
          authOidc = {
            clientId = "paperless";
            clientSecretFile = "/run/secrets/paperless-oidc-client-secret";
            launchUrl = "https://paperless.jax22.com/";
            redirectUris = [ "https://paperless.jax22.com/accounts/oidc/authentik/login/callback/" ];
          };
          smokeHttp.path = "/accounts/login/";
        })
        (mkService {
          id = "forgejo";
          name = "Forgejo";
          port = 3002;
          routeDescription = "Forgejo software forge";
          icon = "forgejo.png";
          homepageDescription = "Gitea community forge\n${backend 3002}";
          authMode = "native-oidc";
          authGroups = [ "productivity-users" ];
          authOidc = {
            clientId = "forgejo";
            clientSecretFile = "/run/secrets/forgejo-oidc-client-secret";
            launchUrl = "https://forgejo.jax22.com/";
            redirectUris = [ "https://forgejo.jax22.com/user/oauth2/authentik/callback" ];
          };
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "openspeedtest";
          name = "OpenSpeedTest";
          port = 8989;
          routeDescription = "OpenSpeedTest browser speed test";
          icon = "openspeedtest.png";
          homepageDescription = "Browser speed test\n${backend 8989}";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "it-tools";
          name = "IT-Tools";
          port = 8093;
          routeDescription = "IT-Tools developer utilities";
          icon = "it-tools.png";
          homepageDescription = "Developer utilities\n${backend 8093}";
          hostNames = [ "it-tools.jax22.com" ];
          homepageSiteMonitor = "${backend 8093}/";
          authMode = "forward-auth";
          authGroups = [ "productivity-users" ];
          checkmate.url = "https://it-tools.jax22.com/";
          smokeHttp = {
            discard = true;
            hosts = [ "it-tools.jax22.com" ];
            path = "/";
          };
        })
        (mkRouteOnly {
          id = "shlink";
          name = "Shlink API";
          port = 8088;
          routeDescription = "Shlink short-link API and redirect service";
          hostPrefix = "s";
          smokeHttp.path = "/rest/health";
        })
        (mkService {
          id = "shlink-web";
          name = "Shlink";
          port = 8089;
          routeDescription = "Shlink Web Client";
          icon = "shlink.png";
          homepageDescription = "Short-link web client\n${backend 8089}";
          hostPrefix = "shlink";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "rustfs-console";
          name = "RustFS Console";
          port = 9001;
          routeDescription = "RustFS object storage console";
          icon = "rustfs.png";
          homepageDescription = "Object storage console\n${backend 9001}";
          hostPrefix = "rustfs";
          monitorPath = "/rustfs/console/health";
          rootRedirectPath = "/rustfs/console/";
          authMode = "native-oidc";
          authGroups = [ "fleet-admins" ];
          authOidc = {
            clientId = "rustfs-console";
            clientSecretFile = "/run/secrets/rustfs-oidc-client-secret";
            launchUrl = "https://rustfs.jax22.com/";
            redirectUris = [ "https://rustfs.jax22.com/rustfs/admin/v3/oidc/callback/authentik" ];
          };
          smokeHttp.path = "/rustfs/console/health";
        })
        (mkService {
          id = "vaultwarden";
          name = "Vaultwarden";
          port = 8222;
          routeDescription = "Vaultwarden password vault";
          icon = "vaultwarden.png";
          homepageDescription = "Password vault\n${backend 8222}";
        })
        (mkService {
          id = "searxng";
          name = "SearXNG";
          port = 8087;
          routeDescription = "SearXNG private metasearch";
          icon = "searxng.png";
          homepageDescription = "Private metasearch\n${backend 8087}";
        })
        (mkService {
          id = "syncthing";
          name = "Syncthing";
          port = 8384;
          routeDescription = "Syncthing file synchronization";
          icon = "syncthing.png";
          homepageDescription = "File synchronization\n${backend 8384}";
        })
        (mkService {
          id = "docs";
          name = "Docs";
          port = 80;
          routeDescription = "Material for MkDocs knowledge base";
          icon = "mkdocs.png";
          homepageDescription = "Material for MkDocs\n${backend 80}";
        })
        (mkService {
          id = "freshrss";
          name = "FreshRSS";
          port = 80;
          routeDescription = "FreshRSS reader";
          icon = "freshrss.png";
          homepageDescription = "RSS reader\n${backend 80}";
          smokeHttp.path = "/i/";
        })
        (mkService {
          id = "privatebin";
          name = "PrivateBin";
          port = 80;
          routeDescription = "PrivateBin temporary text sharing";
          icon = "privatebin.png";
          homepageDescription = "Encrypted temporary text sharing\n${backend 80}";
        })
        (mkService {
          id = "nextcloud";
          name = "Nextcloud";
          port = 80;
          routeDescription = "Nextcloud private cloud files";
          icon = "nextcloud.png";
          homepageDescription = "Private cloud files\n${backend 80}";
          authMode = "native-oidc";
          authGroups = [ "productivity-users" ];
          authOidc = {
            clientId = "nextcloud";
            clientSecretFile = "/run/secrets/nextcloud-oidc-client-secret";
            launchUrl = "https://nextcloud.jax22.com/";
            redirectUris = [ "https://nextcloud.jax22.com/apps/user_oidc/code" ];
            subMode = "user_uuid";
          };
          smokeHttp.path = "/status.php";
        })
        (mkService {
          id = "netbootxyz";
          name = "Netboot.xyz";
          port = 3001;
          routeDescription = "Web configuration UI";
          icon = "netboot.png";
          homepageDescription = "${backend 3001}\nTFTP ${host.ip}:69/udp";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "garage-web";
          name = "Garage";
          port = 3900;
          routeDescription = "Garage static website endpoint";
          icon = "garage.png";
          homepageDescription = "S3-compatible object storage\n${backend 3900}";
          hostPrefix = "s3.garage";
          checkmate.enable = false;
        })
        (mkRouteOnly {
          id = "garage";
          name = "Garage API";
          port = 3900;
          routeDescription = "Garage standalone S3 API";
        })
        (mkService {
          id = "rustfs";
          name = "RustFS";
          port = 9000;
          routeDescription = "RustFS S3-compatible object storage";
          icon = "rustfs.png";
          homepageDescription = "S3-compatible object storage\n${backend 9000}";
          hostPrefix = "s3.rustfs";
          monitorPath = "/health";
          authMode = "none";
          smokeHttp.path = "/health";
        })
        {
          id = "iperf3";
          name = "iperf3";
          docs.urls = builtins.concatMap (hostName: [
            "iperf3 -c ${hostName} -p 5201"
            "iperf3 -u -c ${hostName} -p 5201"
          ]) (hostnames "iperf3");
          homepage = {
            description = "Network throughput test\niperf3 -c iperf3.${builtins.head serviceDomains} -p 5201";
            icon = "mdi-speedometer";
          };
          smoke = {
            dnsHosts = hostnames "iperf3";
            requiredUnit = "traefik.service";
          };
          tcpRoute = {
            description = "iperf3 TCP throughput test";
            entryPoint = "iperf3-tcp";
            port = 5201;
            url = "${host.ip}:5201";
          };
          udpRoute = {
            description = "iperf3 UDP throughput test";
            entryPoint = "iperf3-udp";
            port = 5201;
            url = "${host.ip}:5201";
          };
        }
        {
          id = "rustdesk-signal";
          name = "RustDesk Signal";
          smoke.requiredUnit = "traefik.service";
          tcpRoute = {
            description = "RustDesk hbbs signal TCP";
            entryPoint = "rustdesk-signal-tcp";
            port = 21116;
            url = "${host.ip}:21116";
          };
          udpRoute = {
            description = "RustDesk hbbs signal UDP";
            entryPoint = "rustdesk-signal-udp";
            port = 21116;
            url = "${host.ip}:21116";
          };
        }
        {
          id = "rustdesk-nat-test";
          name = "RustDesk NAT Test";
          smoke.requiredUnit = "traefik.service";
          tcpRoute = {
            description = "RustDesk TCP NAT test";
            entryPoint = "rustdesk-nat-test-tcp";
            port = 21115;
            url = "${host.ip}:21115";
          };
        }
        {
          id = "rustdesk-relay";
          name = "RustDesk Relay";
          smoke.requiredUnit = "traefik.service";
          tcpRoute = {
            description = "RustDesk hbbr relay TCP";
            entryPoint = "rustdesk-relay-tcp";
            port = 21117;
            url = "${host.ip}:21117";
          };
        }
        {
          id = "rustdesk-web-client-1";
          name = "RustDesk Web Client 1";
          smoke.requiredUnit = "traefik.service";
          tcpRoute = {
            description = "RustDesk web client TCP";
            entryPoint = "rustdesk-web-client-1-tcp";
            port = 21118;
            url = "${host.ip}:21118";
          };
        }
        {
          id = "rustdesk-web-client-2";
          name = "RustDesk Web Client 2";
          smoke.requiredUnit = "traefik.service";
          tcpRoute = {
            description = "RustDesk web client TCP";
            entryPoint = "rustdesk-web-client-2-tcp";
            port = 21119;
            url = "${host.ip}:21119";
          };
        }
        {
          id = "rustdesk";
          name = "RustDesk";
          docs.urls = builtins.concatMap (hostName: [
            "rustdesk server: ${hostName}"
            "rustdesk key: /srv/appsdata/rustdesk/id_ed25519.pub"
          ]) (hostnames "rustdesk");
          homepage = {
            description = "Remote desktop relay\nID server rustdesk.${builtins.head serviceDomains}";
            icon = "rustdesk.png";
          };
          smoke = {
            dnsHosts = hostnames "rustdesk";
            requiredUnit = "traefik.service";
          };
        }
      ];
    }
  ];
}
