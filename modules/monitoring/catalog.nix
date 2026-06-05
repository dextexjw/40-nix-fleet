{
  host,
  serviceDomain ? "h",
  serviceDomains ? [ serviceDomain ],
}:

let
  backend = port: "http://${host.ip}:${toString port}";
  hostnames = name: map (domain: "${name}.${domain}") serviceDomains;
  hostname = name: "${name}.${builtins.head serviceDomains}";
  routeUrl =
    name:
    let
      hostName = hostname name;
      scheme = if builtins.match ".*[.]h" hostName != null then "http" else "https";
    in
    "${scheme}://${hostName}";
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
            href = "${routeUrl "checkmate"}/";
            icon = "checkmate.png";
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
          auth = {
            mode = "native-oidc";
            groups = [ "monitoring-users" ];
            oidc = {
              clientId = "beszel";
              clientSecretFile = "/run/secrets/beszel-oidc-client-secret";
              launchUrl = "https://beszel.jax22.com/";
              redirectUris = [ "https://beszel.jax22.com/api/oauth2-redirect" ];
            };
          };
          homepage = {
            description = "Lightweight host monitoring\n${backend 8090}";
            href = "${routeUrl "beszel"}/";
            icon = "beszel.png";
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
