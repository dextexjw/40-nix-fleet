{
  host,
  serviceDomain ? "h",
  serviceDomains ? [ serviceDomain ],
}:

let
  backend = port: "http://${host.ip}:${toString port}";
  hostnames = name: map (domain: "${name}.${domain}") serviceDomains;
  hostname = name: "${name}.${builtins.head serviceDomains}";
in
{
  groups = [
    {
      name = "Monitoring";
      order = 40;
      columns = 4;
      style = "row";
      services = [
        {
          id = "checkmate";
          name = "Checkmate";
          route = {
            description = "Checkmate uptime, status, and infrastructure monitoring";
            hosts = hostnames "checkmate";
            url = backend 52345;
          };
          homepage = {
            description = "Status monitoring and alerts\n${backend 52345}";
            href = "http://${hostname "checkmate"}/";
            icon = "mdi-monitor-dashboard";
            siteMonitor = "${backend 52345}/";
          };
          smoke.http = {
            discard = true;
            path = "/";
          };
        }
        {
          id = "beszel";
          name = "Beszel";
          route = {
            description = "Beszel lightweight host monitoring hub";
            hosts = hostnames "beszel";
            url = backend 8090;
          };
          homepage = {
            description = "Lightweight host monitoring\n${backend 8090}";
            href = "http://${hostname "beszel"}/";
            icon = "mdi-server-network";
            siteMonitor = "${backend 8090}/";
          };
          smoke.http = {
            discard = true;
            path = "/";
          };
        }
      ];
    }
  ];
}
