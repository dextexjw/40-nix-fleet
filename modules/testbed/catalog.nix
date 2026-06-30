{
  host,
  serviceDomain ? "h",
  serviceDomains ? [ serviceDomain ],
}:

let
  backend = port: "http://${host.ip}:${toString port}";
  hostnames = name: map (domain: "${name}.${domain}") serviceDomains;
  urlScheme = hostName: if builtins.match ".*[.]h" hostName != null then "http" else "https";
  publicServiceUrl =
    hostPrefix:
    let
      primaryHostName = builtins.head (hostnames hostPrefix);
    in
    "${urlScheme primaryHostName}://${primaryHostName}/";
in
{
  groups = [
    {
      name = "Testbed";
      order = 40;
      columns = 4;
      style = "row";
      services = [
        {
          id = "listmonk";
          name = "Listmonk";
          route = {
            description = "Listmonk newsletter testbed";
            hosts = hostnames "listmonk";
            url = backend 9000;
          };
          homepage = {
            description = "Newsletter testbed\n${backend 9000}";
            href = publicServiceUrl "listmonk";
            icon = "listmonk.png";
            siteMonitor = "${backend 9000}/admin/login";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "fleet-admins" ];
            oidc = {
              clientId = "listmonk";
              clientSecretFile = "/run/secrets/listmonk-oidc-client-secret";
              launchUrl = "https://listmonk.jax22.com/";
              redirectUris = [ "https://listmonk.jax22.com/auth/oidc" ];
            };
          };
          checkmate.url = "https://listmonk.jax22.com/admin/login";
          smoke.http = {
            discard = true;
            path = "/admin/login";
          };
        }
      ];
    }
  ];
}
