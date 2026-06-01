{ hosts, serviceDomain, ... }:

let
  host = hosts.gateway-vm;
  hostname = name: "${name}.${serviceDomain}";
in
{
  groups = [
    {
      name = "Gateway";
      order = 10;
      columns = 4;
      style = "row";
      services = [
        {
          id = "homepage";
          name = "Homepage";
          route = {
            description = "Homepage service directory";
            host = hostname "homepage";
            url = "http://127.0.0.1:8082";
          };
          homepage = {
            description = "http://${host.ip}:8082";
            href = "http://${hostname "homepage"}/";
            icon = "homepage.png";
            siteMonitor = "http://127.0.0.1:8082/";
          };
          smoke.http.path = "/";
        }
        {
          id = "traefik";
          name = "Traefik";
          docs.urls = [
            "http://${hostname "traefik"}/dashboard/"
            "http://${hostname "traefik"}:8080/dashboard/"
            "http://${hostname "traefik"}:8080/metrics"
          ];
          homepage = {
            description = "http://${host.ip}:8080/dashboard/";
            href = "http://${hostname "traefik"}/dashboard/";
            icon = "traefik.png";
            siteMonitor = "http://127.0.0.1:8080/dashboard/";
          };
          smoke = {
            dnsHosts = [ (hostname "traefik") ];
            http = {
              description = "Traefik dashboard web route";
              host = hostname "traefik";
              path = "/dashboard/";
            };
          };
        }
        {
          id = "technitium";
          name = "Technitium";
          route = {
            description = "Technitium DNS administration and DoH endpoint";
            host = hostname "technitium";
            url = "http://127.0.0.1:5380";
          };
          homepage = {
            description = "http://${host.ip}:5380";
            href = "http://${hostname "technitium"}/";
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
            host = hostname "gluetun";
            url = "http://127.0.0.1:3000";
          };
          homepage = {
            description = "HTTP: 8888 - SOCKS v5: 8388";
            href = "http://${hostname "gluetun"}/";
            icon = "gluetun.png";
            siteMonitor = "http://127.0.0.1:3000/api/health";
          };
          smoke.http.path = "/api/health";
        }
        {
          id = "netbootxyz";
          name = "Netboot.xyz";
          route = {
            description = "netboot.xyz web configuration UI";
            host = hostname "netbootxyz";
            url = "http://127.0.0.1:3001";
          };
          homepage = {
            description = "TFTP ${host.ip}:69/udp";
            href = "http://${hostname "netbootxyz"}/";
            icon = "netboot.png";
            siteMonitor = "http://127.0.0.1:3001/";
          };
          smoke = {
            requiredUnit = "podman-netbootxyz.service";
            http.path = "/";
          };
        }
        {
          id = "traefik-dashboard-ip";
          name = "Traefik Dashboard IP";
          homepage = {
            description = "http://${host.ip}:8080/metrics";
            href = "http://${host.ip}:8080/dashboard/";
            icon = "traefik.png";
            siteMonitor = "http://${host.ip}:8080/dashboard/";
          };
        }
        {
          id = "technitium-direct-ip";
          name = "Technitium Direct IP";
          homepage = {
            description = "http://${hostname "technitium"}/";
            href = "http://${host.ip}:5380/";
            icon = "technitium.png";
            siteMonitor = "http://${host.ip}:5380/";
          };
        }
        {
          id = "wildcard-gateway-validation";
          name = "Wildcard Gateway Validation";
          smoke.dnsHosts = [ (hostname "wildcard-gateway-validation") ];
        }
      ];
    }
  ];
}
