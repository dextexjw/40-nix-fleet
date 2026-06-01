{ host, serviceDomain }:

let
  backend = port: "http://${host.ip}:${toString port}";
  hostname = name: "${name}.${serviceDomain}";

  mkService =
    {
      id,
      name,
      port,
      routeDescription,
      icon,
      homepageDescription ? backend port,
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
        siteMonitor = "${backend port}${monitorPath}";
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
      name = "Media";
      order = 20;
      columns = 4;
      style = "row";
      services = [
        (mkService {
          id = "jellyfin";
          name = "Jellyfin";
          port = 8096;
          routeDescription = "Jellyfin media server";
          icon = "jellyfin.png";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "audiobookshelf";
          name = "Audiobookshelf";
          port = 8000;
          routeDescription = "Audiobookshelf media library";
          icon = "audiobookshelf.png";
        })
        (mkService {
          id = "kavita";
          name = "Kavita";
          port = 5000;
          routeDescription = "Kavita library";
          icon = "kavita.png";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "sonarr";
          name = "Sonarr";
          port = 8989;
          routeDescription = "Sonarr TV management";
          icon = "sonarr.png";
        })
        (mkService {
          id = "radarr";
          name = "Radarr";
          port = 7878;
          routeDescription = "Radarr movie management";
          icon = "radarr.png";
        })
        (mkService {
          id = "prowlarr";
          name = "Prowlarr";
          port = 9696;
          routeDescription = "Prowlarr indexer management";
          icon = "prowlarr.png";
        })
        (mkService {
          id = "bazarr";
          name = "Bazarr";
          port = 6767;
          routeDescription = "Bazarr subtitle management";
          icon = "bazarr.png";
          homepageDescription = "Subtitles ${backend 6767}";
        })
        (mkService {
          id = "qbittorrent";
          name = "qBittorrent";
          port = 8080;
          routeDescription = "qBittorrent downloads";
          icon = "qbittorrent.png";
        })
        (mkService {
          id = "media-gluetun";
          name = "Media Gluetun";
          port = 3001;
          routeDescription = "MediaVM Gluetun WebUI for download clients";
          icon = "gluetun.png";
          homepageDescription = "media VPN @ ${backend 3001}";
          monitorPath = "/api/health";
          smokeHttp.path = "/api/health";
        })
        (mkService {
          id = "sabnzbd";
          name = "SABnzbd";
          port = 8085;
          routeDescription = "SABnzbd downloads";
          icon = "sabnzbd.png";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
        (mkService {
          id = "seerr";
          name = "Seerr";
          port = 5055;
          routeDescription = "Seerr requests";
          icon = "seerr.png";
          smokeHttp = {
            discard = true;
            path = "/";
          };
        })
      ];
    }
  ];
}
