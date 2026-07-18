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
          id = "affine";
          name = "AFFiNE";
          route = {
            description = "AFFiNE collaborative workspace";
            hosts = hostnames "affine";
            url = backend 3010;
          };
          homepage = {
            description = "Collaborative workspace\n${backend 3010}";
            href = publicServiceUrl "affine";
            icon = "affine.png";
            siteMonitor = "${backend 3010}/";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "productivity-users" ];
            oidc = {
              clientId = "affine";
              clientSecretFile = "/run/secrets/affine-oidc-client-secret";
              launchUrl = "https://affine.jax22.com/";
              redirectUris = [ "https://affine.jax22.com/oauth/callback" ];
            };
          };
          smoke.http = {
            discard = true;
            path = "/";
          };
        }
        {
          id = "gitea";
          name = "Gitea";
          route = {
            description = "Gitea Git repositories";
            hosts = hostnames "gitea";
            url = backend 9070;
          };
          homepage = {
            description = "Git repositories\n${backend 9070}";
            href = publicServiceUrl "gitea";
            icon = "gitea.png";
            siteMonitor = "${backend 9070}/";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "productivity-users" ];
            oidc = {
              clientId = "gitea";
              clientSecretFile = "/run/secrets/gitea-oidc-client-secret";
              launchUrl = "https://gitea.jax22.com/";
              redirectUris = [ "https://gitea.jax22.com/user/oauth2/authentik/callback" ];
            };
          };
          smoke.http = {
            discard = true;
            path = "/";
          };
        }
        {
          id = "stirling-pdf";
          name = "Stirling PDF";
          route = {
            description = "Stirling PDF toolkit";
            hosts = hostnames "stirling-pdf";
            url = backend 8086;
          };
          homepage = {
            description = "PDF toolkit\n${backend 8086}";
            href = publicServiceUrl "stirling-pdf";
            icon = "stirling-pdf.png";
            siteMonitor = "${backend 8086}/";
          };
          smoke.http = {
            discard = true;
            okStatusPatterns = [
              "2*"
              "30[1278]"
              "401"
              "403"
            ];
            path = "/";
          };
        }
        {
          id = "firefly";
          name = "Firefly III";
          route = {
            description = "Firefly III personal finance";
            hosts = hostnames "firefly";
            url = backend 80;
          };
          homepage = {
            description = "Personal finance\n${backend 80}";
            href = publicServiceUrl "firefly";
            icon = "firefly-iii.png";
            siteMonitor = "${backend 80}/";
          };
          smoke.http = {
            discard = true;
            path = "/";
          };
        }
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
          id = "invoiceplane";
          name = "InvoicePlane";
          route = {
            description = "InvoicePlane invoice management testbed";
            hosts = hostnames "invoiceplane";
            url = backend 9060;
          };
          homepage = {
            description = "Invoice management testbed\n${backend 9060}";
            href = publicServiceUrl "invoiceplane";
            icon = "invoiceplane.png";
            siteMonitor = "${backend 9060}/sessions/login";
          };
          auth = {
            mode = "forward-auth";
            groups = [ "fleet-admins" ];
          };
          checkmate.url = "https://invoiceplane.jax22.com/sessions/login";
          smoke.http = {
            discard = true;
            path = "/sessions/login";
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
            icon = "https://raw.githubusercontent.com/usekaneo/kaneo/36683724fecc94969dcc2350ab49a6cc7686bb11/apps/web/public/web-app-manifest-512x512.png";
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
          id = "karakeep";
          name = "Karakeep";
          route = {
            description = "Karakeep bookmark and read-it-later manager";
            hosts = hostnames "karakeep";
            url = backend 9090;
          };
          homepage = {
            description = "Bookmark and read-it-later manager\n${backend 9090}";
            href = publicServiceUrl "karakeep";
            icon = "karakeep.png";
            siteMonitor = "${backend 9090}/";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "fleet-admins" ];
            oidc = {
              clientId = "karakeep";
              clientSecretFile = "/run/secrets/karakeep-oidc-client-secret";
              launchUrl = "https://karakeep.jax22.com/";
              redirectUris = [ "https://karakeep.jax22.com/api/auth/callback/custom" ];
            };
          };
          checkmate.url = "https://karakeep.jax22.com/";
          smoke.http = {
            discard = true;
            path = "/";
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
          id = "outline";
          name = "Outline";
          route = {
            description = "Outline knowledge-base testbed";
            hosts = hostnames "outline";
            url = backend 9050;
          };
          homepage = {
            description = "Knowledge-base testbed\n${backend 9050}";
            href = publicServiceUrl "outline";
            icon = "outline.png";
            siteMonitor = "${backend 9050}/_health";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "fleet-admins" ];
            oidc = {
              clientId = "outline";
              clientSecretFile = "/run/secrets/outline-oidc-client-secret";
              launchUrl = "https://outline.jax22.com/";
              redirectUris = [ "https://outline.jax22.com/auth/oidc.callback" ];
            };
          };
          checkmate.url = "https://outline.jax22.com/_health";
          smoke.http = {
            discard = true;
            path = "/_health";
          };
        }
        {
          id = "plane";
          name = "Plane";
          route = {
            description = "Plane project-management testbed";
            hosts = publicHostnames "plane";
            url = backend 9020;
          };
          homepage = {
            description = "Project-management testbed\n${backend 9020}";
            href = publicOnlyServiceUrl "plane";
            icon = "plane.png";
            siteMonitor = "${backend 9020}/api/instances/";
          };
          auth = {
            mode = "forward-auth";
            groups = [ "fleet-admins" ];
          };
          checkmate.url = "https://plane.jax22.com/api/instances/";
          smoke.http = {
            discard = true;
            path = "/api/instances/";
          };
        }
        {
          id = "postiz";
          name = "Postiz";
          route = {
            description = "Postiz social media scheduling testbed";
            hosts = hostnames "postiz";
            url = backend 9040;
          };
          homepage = {
            description = "Social media scheduling testbed\n${backend 9040}";
            href = publicServiceUrl "postiz";
            icon = "https://raw.githubusercontent.com/gitroomhq/postiz-app/d167233e063bb172b84d0bdf5ad563cff28778e9/apps/frontend/public/postiz-fav.png";
            siteMonitor = "${backend 9040}/";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "fleet-admins" ];
            oidc = {
              clientId = "postiz";
              clientSecretFile = "/run/secrets/postiz-oidc-client-secret";
              launchUrl = "https://postiz.jax22.com/";
              redirectUris = [ "https://postiz.jax22.com/settings" ];
            };
          };
          checkmate.url = "https://postiz.jax22.com/";
          smoke.http = {
            discard = true;
            path = "/";
          };
        }
        {
          id = "sure";
          name = "Sure";
          route = {
            description = "Sure personal finance testbed";
            hosts = hostnames "sure";
            url = backend 9030;
          };
          homepage = {
            description = "Personal finance testbed\n${backend 9030}";
            href = publicServiceUrl "sure";
            icon = "https://raw.githubusercontent.com/we-promise/sure/f51b24096795a15f3d0aae6c860398e8470bfe0f/app/assets/images/logo-color.png";
            siteMonitor = "${backend 9030}/up";
          };
          auth = {
            mode = "native-oidc";
            groups = [ "fleet-admins" ];
            oidc = {
              clientId = "sure";
              clientSecretFile = "/run/secrets/sure-oidc-client-secret";
              launchUrl = "https://sure.jax22.com/";
              redirectUris = [ "https://sure.jax22.com/auth/openid_connect/callback" ];
            };
          };
          checkmate.url = "https://sure.jax22.com/up";
          smoke.http = {
            discard = true;
            path = "/up";
          };
        }
        {
          id = "metube";
          name = "MeTube";
          route = {
            description = "MeTube video downloader testbed";
            hosts = publicHostnames "metube";
            url = backend 8081;
          };
          homepage = {
            description = "Video downloader testbed\n${backend 8081}";
            href = publicOnlyServiceUrl "metube";
            icon = "metube.png";
            siteMonitor = "${backend 8081}/";
          };
          auth = {
            mode = "forward-auth";
            groups = [ "fleet-admins" ];
          };
          checkmate.url = "https://metube.jax22.com/";
          smoke.http = {
            discard = true;
            path = "/";
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
        {
          id = "mailpit-smtp";
          name = "Mailpit SMTP";
          docs.urls = [ "smtp.mailpit.jax22.com:25" ];
          smoke = {
            dnsHosts = [ "smtp.mailpit.jax22.com" ];
            requiredUnit = "traefik.service";
          };
          tcpRoute = {
            description = "Mailpit SMTP capture";
            entryPoint = "mailpit-smtp";
            port = 25;
            url = "${host.ip}:1025";
          };
        }
      ];
    }
  ];
}
