{ host, serviceDomain }:

let
  backend = port: "http://${host.ip}:${toString port}";
  hostname = name: "${name}.${serviceDomain}";
  monitorBase = port: if port == 80 then "http://${host.ip}" else backend port;

  mkService =
    {
      id,
      name,
      port,
      routeDescription,
      icon,
      homepageDescription,
      hostName ? hostname id,
      monitorPath ? "/",
      smokeHttp ? null,
    }:
    {
      inherit id name;
      route = {
        description = routeDescription;
        host = hostName;
        url = backend port;
      };
      homepage = {
        description = homepageDescription;
        href = "http://${hostName}/";
        inherit icon;
        siteMonitor = "${monitorBase port}${monitorPath}";
      };
    }
    // (
      if smokeHttp == null then
        { }
      else
        {
          smoke.http = smokeHttp;
        }
    );

  mkRouteOnly =
    {
      id,
      name,
      port,
      routeDescription,
      hostName ? hostname id,
      smokeHttp ? null,
    }:
    {
      inherit id name;
      route = {
        description = routeDescription;
        host = hostName;
        url = backend port;
      };
    }
    // (
      if smokeHttp == null then
        { }
      else
        {
          smoke.http = smokeHttp;
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
          id = "gitea";
          name = "Gitea";
          port = 3000;
          routeDescription = "Gitea Git repositories";
          icon = "gitea.png";
          homepageDescription = "Git repositories\n${backend 3000}";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "forgejo";
          name = "Forgejo";
          port = 3002;
          routeDescription = "Forgejo software forge";
          icon = "forgejo.png";
          homepageDescription = "Gitea community forge\n${backend 3002}";
          smokeHttp = {
            discard = true;
            path = "/";
          };
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
          id = "paperless";
          name = "Paperless";
          port = 80;
          routeDescription = "Paperless-ngx document archive";
          icon = "paperless-ngx.png";
          homepageDescription = "Document OCR and archive\n${backend 80}";
        })
        (mkService {
          id = "freshrss";
          name = "FreshRSS";
          port = 80;
          routeDescription = "FreshRSS reader";
          icon = "freshrss.png";
          homepageDescription = "RSS reader\n${backend 80}";
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
          id = "privatebin";
          name = "PrivateBin";
          port = 80;
          routeDescription = "PrivateBin temporary text sharing";
          icon = "privatebin.png";
          homepageDescription = "Encrypted temporary text sharing\n${backend 80}";
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
          id = "syncthing";
          name = "Syncthing";
          port = 8384;
          routeDescription = "Syncthing file synchronization";
          icon = "syncthing.png";
          homepageDescription = "File synchronization\n${backend 8384}";
        })
        (mkService {
          id = "stirling-pdf";
          name = "Stirling PDF";
          port = 8086;
          routeDescription = "Stirling PDF toolkit";
          icon = "stirling-pdf.png";
          homepageDescription = "PDF toolkit\n${backend 8086}";
        })
        (mkService {
          id = "firefly";
          name = "Firefly III";
          port = 80;
          routeDescription = "Firefly III personal finance";
          icon = "firefly-iii.png";
          homepageDescription = "Personal finance\n${backend 80}";
        })
        (mkService {
          id = "nextcloud";
          name = "Nextcloud";
          port = 80;
          routeDescription = "Nextcloud private cloud files";
          icon = "nextcloud.png";
          homepageDescription = "Private cloud files\n${backend 80}";
        })
        (mkRouteOnly {
          id = "shlink";
          name = "Shlink API";
          port = 8088;
          routeDescription = "Shlink short-link API and redirect service";
          hostName = hostname "s";
          smokeHttp.path = "/rest/health";
        })
        (mkService {
          id = "shlink-web";
          name = "Shlink";
          port = 8089;
          routeDescription = "Shlink Web Client";
          icon = "shlink.png";
          homepageDescription = "Short-link web client\n${backend 8089}";
          hostName = hostname "shlink";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkRouteOnly {
          id = "garage";
          name = "Garage API";
          port = 3900;
          routeDescription = "Garage standalone S3 API";
        })
        (mkService {
          id = "garage-web";
          name = "Garage";
          port = 3902;
          routeDescription = "Garage static website endpoint";
          icon = "garage.png";
          homepageDescription = "Static website endpoint\n${backend 3902}";
        })
        (mkService {
          id = "rustfs";
          name = "RustFS";
          port = 9000;
          routeDescription = "RustFS S3-compatible object storage";
          icon = "rustfs.png";
          homepageDescription = "S3-compatible object storage\n${backend 9000}";
          monitorPath = "/health";
          smokeHttp.path = "/health";
        })
        (mkService {
          id = "rustfs-console";
          name = "RustFS Console";
          port = 9001;
          routeDescription = "RustFS object storage console";
          icon = "rustfs.png";
          homepageDescription = "Object storage console\n${backend 9001}";
          monitorPath = "/rustfs/console/health";
          smokeHttp.path = "/rustfs/console/health";
        })
        (mkService {
          id = "ntfy";
          name = "ntfy";
          port = 2586;
          routeDescription = "ntfy push notifications";
          icon = "ntfy.png";
          homepageDescription = "Push notifications\n${backend 2586}";
          monitorPath = "/v1/health";
        })
      ];
    }
  ];
}
