{
  host,
  serviceDomain ? "h",
  serviceDomains ? [ serviceDomain ],
}:

let
  backend = port: "http://${host.ip}:${toString port}";
  hostnames = name: map (domain: "${name}.${domain}") serviceDomains;
  publicHostnames =
    name:
    let
      candidates = builtins.filter (hostName: builtins.match ".*[.]h" hostName == null) (hostnames name);
    in
    if candidates == [ ] then hostnames name else candidates;
  urlScheme = hostName: if builtins.match ".*[.]h" hostName != null then "http" else "https";
  publicServiceUrl =
    hostPrefix:
    let
      primaryHostName = builtins.head (hostnames hostPrefix);
    in
    "${urlScheme primaryHostName}://${primaryHostName}/";
  publicOnlyServiceUrl =
    hostPrefix:
    let
      primaryHostName = builtins.head (publicHostnames hostPrefix);
    in
    "https://${primaryHostName}/";
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
          id = "fizzy";
          name = "Fizzy";
          route = {
            description = "Fizzy project board testbed";
            hosts = hostnames "fizzy";
            url = backend 9010;
          };
          homepage = {
            description = "Project board testbed\n${backend 9010}";
            href = publicServiceUrl "fizzy";
            icon = "https://pb.dashboardicons.com/api/files/community_gallery/lgxof2ccfr6q7gq/apple_touch_icon_omijen1jki.png";
            siteMonitor = "${backend 9010}/up";
          };
          auth = {
            mode = "forward-auth";
            groups = [ "fleet-admins" ];
          };
          checkmate.url = "https://fizzy.jax22.com/up";
          smoke.http = {
            discard = true;
            path = "/up";
          };
        }
        {
          id = "keeper";
          name = "Keeper";
          route = {
            description = "Keeper calendar sync testbed";
            hosts = publicHostnames "keeper";
            url = backend 3000;
          };
          homepage = {
            description = "Calendar sync testbed\n${backend 3000}";
            href = publicOnlyServiceUrl "keeper";
            icon = "https://pb.dashboardicons.com/api/files/community_gallery/4avgzq0ktz2jb7h/180x180_light_on_dark_qx83v0wqus.png";
            siteMonitor = "${backend 3000}/";
          };
          auth = {
            mode = "forward-auth";
            groups = [ "fleet-admins" ];
          };
          checkmate.url = "https://keeper.jax22.com/";
          smoke.http = {
            discard = true;
            path = "/";
          };
        }
        {
          id = "homebox";
          name = "Homebox";
          route = {
            description = "Home inventory testbed";
            hosts = hostnames "homebox";
            url = backend 7745;
          };
          homepage = {
            description = "Home inventory testbed\n${backend 7745}";
            href = publicServiceUrl "homebox";
            icon = "homebox.png";
            siteMonitor = "${backend 7745}/api/v1/status";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "fleet-admins" ];
            oidc = {
              clientId = "homebox";
              clientSecretFile = "/run/secrets/homebox-oidc-client-secret";
              launchUrl = "https://homebox.jax22.com/";
              redirectUris = [ "https://homebox.jax22.com/api/v1/users/login/oidc/callback" ];
            };
          };
          checkmate.url = "https://homebox.jax22.com/api/v1/status";
          smoke.http = {
            discard = true;
            path = "/api/v1/status";
          };
        }
        {
          id = "kaneo";
          name = "Kaneo";
          route = {
            description = "Kaneo project-management testbed";
            hosts = hostnames "kaneo";
            url = backend 5173;
          };
          homepage = {
            description = "Project-management testbed\n${backend 5173}";
            href = publicServiceUrl "kaneo";
            icon = "mdi-view-dashboard-edit";
            siteMonitor = "${backend 5173}/api/health";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "fleet-admins" ];
            oidc = {
              clientId = "kaneo";
              clientSecretFile = "/run/secrets/kaneo-oidc-client-secret";
              launchUrl = "https://kaneo.jax22.com/";
              redirectUris = [ "https://kaneo.jax22.com/api/auth/oauth2/callback/custom" ];
            };
          };
          checkmate.url = "https://kaneo.jax22.com/api/health";
          smoke.http = {
            discard = true;
            path = "/api/health";
          };
        }
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
        {
          id = "mailpit";
          name = "Mailpit";
          route = {
            description = "Local SMTP capture inbox for testbed sign-in mail";
            hosts = publicHostnames "mailpit";
            url = backend 8025;
          };
          homepage = {
            description = "Captured testbed email\n${backend 8025}";
            href = publicOnlyServiceUrl "mailpit";
            icon = "mailpit.png";
            siteMonitor = "${backend 8025}/api/v1/messages";
          };
          auth = {
            mode = "forward-auth";
            groups = [ "fleet-admins" ];
          };
          smoke.http = {
            discard = true;
            path = "/api/v1/messages";
          };
        }
      ];
    }
  ];
}
