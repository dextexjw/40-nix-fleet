{
  gatewayHost ? hosts.gateway-vm,
  hosts,
  serviceDomain,
  serviceDomains ? [ serviceDomain ],
  ...
}:

let
  host = gatewayHost;
  hostname = name: "${name}.${builtins.head serviceDomains}";
  hostnames = name: map (domain: "${name}.${domain}") serviceDomains;
  urlScheme = hostName: if builtins.match ".*[.]h" hostName != null then "http" else "https";
  routeUrl = hostName: "${urlScheme hostName}://${hostName}";
in
{
  groups = [
    {
      name = "Homelab";
      order = 5;
      columns = 4;
      style = "row";
      services = [
        {
          id = "unifi-admin";
          name = "UniFi Admin";
          homepage = {
            description = "https://10.2.0.1/";
            href = "https://10.2.0.1/";
            icon = "unifi.png";
            siteMonitor = "https://10.2.0.1/";
          };
        }
        {
          id = "synology-nas";
          name = "Synology NAS";
          homepage = {
            description = "http://nas.home.arpa:5000/";
            href = "http://nas.home.arpa:5000/";
            icon = "synology.png";
            siteMonitor = "http://nas.home.arpa:5000/";
          };
        }
        {
          id = "proxmox";
          name = "Proxmox";
          homepage = {
            description = "https://pve1.home.arpa:8006/";
            href = "https://pve1.home.arpa:8006/";
            icon = "proxmox.png";
            siteMonitor = "https://pve1.home.arpa:8006/";
          };
        }
        {
          id = "home-assistant";
          name = "Home Assistant";
          homepage = {
            description = "http://ha.home.arpa:8123/";
            href = "http://ha.home.arpa:8123/";
            icon = "home-assistant.png";
            siteMonitor = "http://ha.home.arpa:8123/";
          };
        }
      ];
    }
    {
      name = "Gateway";
      order = 10;
      columns = 4;
      style = "row";
      services = [
        {
          id = "authentik";
          name = "Authentik";
          route = {
            description = "Authentik fleet identity provider";
            hosts = [
              "auth.jax22.com"
              "auth.h"
            ];
            url = "http://127.0.0.1:9000";
          };
          homepage = {
            description = " http://${host.ip}:9000";
            href = "https://auth.jax22.com/";
            icon = "authentik.png";
            siteMonitor = "http://127.0.0.1:9000/-/health/ready/";
          };
          smoke = {
            requiredUnit = "authentik-server.service";
            http = {
              hosts = [
                "auth.jax22.com"
                "auth.h"
              ];
              path = "/-/health/ready/";
            };
          };
        }
        {
          id = "homepage";
          name = "Homepage";
          route = {
            description = "Homepage service directory";
            hosts = hostnames "homepage";
            url = "http://127.0.0.1:8082";
          };
          homepage = {
            description = "http://${host.ip}:8082";
            href = "${routeUrl (hostname "homepage")}/";
            icon = "homepage.png";
            siteMonitor = "http://127.0.0.1:8082/";
          };
          smoke.http.path = "/";
        }
        {
          id = "traefik";
          name = "Traefik";
          docs.urls = [
            "${routeUrl (hostname "traefik")}/dashboard/"
            "http://${hostname "traefik"}:8080/dashboard/"
            "http://${hostname "traefik"}:8080/metrics"
          ];
          homepage = {
            description = "http://${host.ip}:8080/dashboard/";
            href = "${routeUrl (hostname "traefik")}/dashboard/";
            icon = "traefik.png";
            siteMonitor = "http://127.0.0.1:8080/dashboard/";
          };
          smoke = {
            dnsHosts = hostnames "traefik";
            http = {
              description = "Traefik dashboard web route";
              hosts = hostnames "traefik";
              path = "/dashboard/";
            };
          };
        }
        {
          id = "technitium";
          name = "Technitium";
          route = {
            description = "Technitium DNS administration and DoH endpoint";
            hosts = hostnames "technitium";
            url = "http://127.0.0.1:5380";
          };
          homepage = {
            description = "http://${host.ip}:5380";
            href = "${routeUrl (hostname "technitium")}/";
            icon = "technitium.png";
            siteMonitor = "http://127.0.0.1:5380/";
          };
          smoke.http.path = "/";
        }
        {
          id = "gluetun";
          name = "Gluetun";
          route = {
            description = "Gluetun WebUI";
            hosts = hostnames "gluetun.gateway";
            url = "http://127.0.0.1:3000";
          };
          homepage = {
            description = "HTTP: 8888 - SOCKS v5: 8388";
            href = "${routeUrl (hostname "gluetun.gateway")}/";
            icon = "gluetun.png";
            siteMonitor = "http://127.0.0.1:3000/api/health";
          };
          checkmate.url = "https://gluetun.gateway.jax22.com/";
          smoke.http.path = "/api/health";
        }
        {
          id = "wildcard-gateway-validation";
          name = "Wildcard Gateway Validation";
          smoke.dnsHosts = hostnames "wildcard-gateway-validation";
        }
      ];
    }
  ];
}
