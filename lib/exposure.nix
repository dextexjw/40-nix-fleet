{
  lib,
  root ? ../.,
}:

with lib;

let
  hostExposurePath = name: root + "/hosts/${name}/exposure.nix";

  loadHostExposure =
    {
      gatewayHost,
      hosts,
      serviceDomain,
      serviceDomains,
      name,
    }:
    import (hostExposurePath name) {
      inherit
        gatewayHost
        hosts
        lib
        serviceDomain
        serviceDomains
        ;
    };

  sortGroups = sort (
    left: right:
    if (left.order or 1000) == (right.order or 1000) then
      left.name < right.name
    else
      (left.order or 1000) < (right.order or 1000)
  );

  primaryRouteHost = route: head route.hosts;

  routeScheme = hostName: if hasSuffix ".h" hostName then "http" else "https";
  isPublicTlsHost = hostName: hasSuffix ".jax22.com" hostName;

  serviceAuth =
    service:
    let
      route = service.route or null;
      auth = service.auth or { };
      mode = auth.mode or "none";
      defaultProtectedHosts = if route == null then [ ] else filter isPublicTlsHost route.hosts;
    in
    {
      inherit mode;
      groups = auth.groups or [ ];
      protectedHosts = auth.protectedHosts or defaultProtectedHosts;
    };

  mkHttpCommand =
    http: hostName:
    let
      path = http.path or "/";
      curl = if http.discard or false then "curl -fsS -o /dev/null" else "curl -fsS";
      okStatusPatterns = http.okStatusPatterns or [ ];
      okStatusCase = concatStringsSep "|" okStatusPatterns;
    in
    http.command or (
      if okStatusPatterns != [ ] then
        "status=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Host: ${hostName}' http://127.0.0.1${path}); case \"$status\" in ${okStatusCase}) exit 0 ;; *) echo \"unexpected status $status\" >&2; exit 1 ;; esac"
      else
        "${curl} -H 'Host: ${hostName}' http://127.0.0.1${path} >/dev/null"
    );

  mkHttpsCommand =
    service: http: hostName:
    let
      path = http.path or "/";
      curl = if http.discard or false then "curl -fsS -o /dev/null" else "curl -fsS";
      auth = serviceAuth service;
      expectsAuth = auth.mode == "forward-auth" && elem hostName auth.protectedHosts;
      okStatusPatterns = http.okStatusPatterns or [ ];
      okStatusCase = concatStringsSep "|" okStatusPatterns;
    in
    http.httpsCommand or (
      if okStatusPatterns != [ ] then
        "status=$(curl -sS -o /dev/null -w '%{http_code}' --resolve '${hostName}:443:127.0.0.1' https://${hostName}${path}); case \"$status\" in ${okStatusCase}) exit 0 ;; *) echo \"unexpected status $status\" >&2; exit 1 ;; esac"
      else if expectsAuth then
        "status=$(curl -sS -o /dev/null -w '%{http_code}' --resolve '${hostName}:443:127.0.0.1' https://${hostName}${path}); case \"$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected auth status $status\" >&2; exit 1 ;; esac"
      else
        "${curl} --resolve '${hostName}:443:127.0.0.1' https://${hostName}${path} >/dev/null"
    );

  routeDefaultDocs =
    service:
    let
      route = service.route or null;
    in
    optionals (route != null) (map (host: "${routeScheme host}://${host}") route.hosts);

  serviceDocs =
    service:
    if service ? docs && service.docs ? urls then service.docs.urls else routeDefaultDocs service;

  mkRoute =
    service:
    nameValuePair service.id (
      {
        inherit (service.route) description hosts url;
        auth = serviceAuth service;
      }
      // optionalAttrs (service.route ? rootRedirectPath) {
        inherit (service.route) rootRedirectPath;
      }
    );

  mkTcpRoute =
    service:
    nameValuePair service.id {
      inherit (service.tcpRoute)
        description
        entryPoint
        port
        url
        ;
    };

  mkUdpRoute =
    service:
    nameValuePair service.id {
      inherit (service.udpRoute)
        description
        entryPoint
        port
        url
        ;
    };

  mkHomepageService =
    service:
    let
      homepage = service.homepage;
      route = service.route or null;
    in
    {
      inherit (service) name;
      description = homepage.description or (if route == null then "" else route.description);
      href = homepage.href or "";
      icon = homepage.icon or null;
      siteMonitor = homepage.siteMonitor or null;
    };

  mkHomepageGroup = group: {
    inherit (group) name;
    services = map mkHomepageService (
      filter (service: (service.homepage or null) != null) group.services
    );
  };

  mkAuthentikApplication =
    service:
    let
      auth = serviceAuth service;
      serviceAuthConfig = service.auth or { };
    in
    {
      slug = service.id;
      name = service.name;
      mode = auth.mode;
      groups = auth.groups;
      hosts = service.route.hosts;
      oidc = serviceAuthConfig.oidc or { };
    };

  mkHomepageLayout = group: {
    ${group.name} = {
      columns = group.columns or 4;
      style = group.style or "row";
    };
  };

  mkDnsRows =
    dnsExpectedAddress: service:
    let
      route = service.route or null;
      smoke = service.smoke or { };
      requiredUnit = smoke.requiredUnit or "";
      hosts =
        if smoke ? dnsHosts then
          smoke.dnsHosts
        else if (smoke.dns or (route != null)) && route != null then
          route.hosts
        else
          [ ];
      expected = smoke.dnsExpected or dnsExpectedAddress;
    in
    map (host: [
      "dns"
      host
      expected
      requiredUnit
    ]) hosts;

  mkHttpRows =
    service:
    let
      route = service.route or null;
      smoke = service.smoke or { };
      http = smoke.http or null;
      canonicalHost = if route == null then null else primaryRouteHost route;
      hostNames =
        if http == null then
          [ ]
        else if http ? hosts then
          http.hosts
        else if http ? host then
          [ http.host ]
        else if route != null then
          route.hosts
        else
          [ ];
      requiredUnit = (http.requiredUnit or (smoke.requiredUnit or ""));
    in
    optionals (http != null && (http.enable or true)) (
      map (hostName: [
        "http"
        (http.description or (
          "${service.name} route"
          + optionalString (canonicalHost != null && hostName != canonicalHost) " (${hostName})"
        )
        )
        (mkHttpCommand http hostName)
        requiredUnit
      ]) hostNames
    );

  mkHttpsRows =
    service:
    let
      route = service.route or null;
      smoke = service.smoke or { };
      http = smoke.http or null;
      canonicalHost = if route == null then null else primaryRouteHost route;
      hostNames =
        if http == null then
          [ ]
        else if http ? hosts then
          http.hosts
        else if http ? host then
          [ http.host ]
        else if route != null then
          route.hosts
        else
          [ ];
      httpsHostNames = filter (hostName: routeScheme hostName == "https") hostNames;
      requiredUnit = (http.requiredUnit or (smoke.requiredUnit or ""));
    in
    optionals (http != null && (http.enable or true)) (
      map (hostName: [
        "http"
        (http.httpsDescription or (
          "${service.name} HTTPS route"
          + optionalString (canonicalHost != null && hostName != canonicalHost) " (${hostName})"
        )
        )
        (mkHttpsCommand service http hostName)
        requiredUnit
      ]) httpsHostNames
    );

  mkAuthentikOidcRows =
    service:
    let
      auth = serviceAuth service;
      serviceAuthConfig = service.auth or { };
      oidc = serviceAuthConfig.oidc or { };
      clientId = oidc.clientId or service.id;
      redirectUris = oidc.redirectUris or [ ];
      authHost = "auth.jax22.com";
      requiredUnit = "authentik-provision.service";
      discoveryCommand = "curl -fsS --resolve '${authHost}:443:127.0.0.1' https://${authHost}/application/o/${clientId}/.well-known/openid-configuration | grep -Fq '\"issuer\"'";
      mkAuthorizeCommand =
        redirectUri:
        "tmp=$(mktemp); trap 'rm -f \"$tmp\"' EXIT; status=$(curl -sS -o \"$tmp\" -w '%{http_code}' --resolve '${authHost}:443:127.0.0.1' --get 'https://${authHost}/application/o/authorize/' --data-urlencode 'client_id=${clientId}' --data-urlencode 'redirect_uri=${redirectUri}' --data-urlencode 'response_type=code' --data-urlencode 'scope=openid profile email' --data-urlencode 'state=fleet-smoke' --data-urlencode 'nonce=fleet-smoke'); case \"$status\" in 2*|3*) ! grep -Eiq 'invalid(_| |-)?(client|redirect)' \"$tmp\" ;; *) echo \"unexpected authorize status $status\" >&2; exit 1 ;; esac";
    in
    optionals (auth.mode == "native-oidc") (
      [
        [
          "http"
          "${service.name} Authentik discovery"
          discoveryCommand
          requiredUnit
        ]
      ]
      ++ map (redirectUri: [
        "http"
        "${service.name} Authentik authorize"
        (mkAuthorizeCommand redirectUri)
        requiredUnit
      ]) redirectUris
    );

  mkHomepageRows =
    service:
    let
      homepage = service.homepage or null;
      smoke = service.smoke or { };
      requiredUnit = smoke.requiredUnit or "";
      homepageHref = homepage.href or null;
    in
    optionals (homepage != null) (
      optional (homepageHref != null) [
        "homepage"
        "${service.name} href"
        "/etc/homepage-dashboard/services.yaml"
        homepageHref
        requiredUnit
      ]
      ++ optional ((homepage.siteMonitor or null) != null) [
        "homepage"
        "${service.name} monitor"
        "/etc/homepage-dashboard/services.yaml"
        homepage.siteMonitor
        requiredUnit
      ]
    );

  mkHomepageGroupRows = group: [
    [
      "homepage"
      "${group.name} layout"
      "/etc/homepage-dashboard/settings.yaml"
      "${group.name}:"
      ""
    ]
    [
      "homepage"
      "${group.name} columns"
      "/etc/homepage-dashboard/settings.yaml"
      "columns: ${toString (group.columns or 4)}"
      ""
    ]
  ];

  mkTcpRows =
    service:
    let
      tcpRoute = service.tcpRoute or null;
      smoke = service.smoke or { };
      requiredUnit = smoke.requiredUnit or "";
    in
    optionals (tcpRoute != null) [
      [
        "tcp"
        service.name
        (toString tcpRoute.port)
        requiredUnit
      ]
    ];

  mkUdpRows =
    service:
    let
      udpRoute = service.udpRoute or null;
      smoke = service.smoke or { };
      requiredUnit = smoke.requiredUnit or "";
    in
    optionals (udpRoute != null) [
      [
        "udp"
        service.name
        (toString udpRoute.port)
        requiredUnit
      ]
    ];

  toTsv = row: concatStringsSep "\t" row;
in
{
  load =
    {
      hosts,
      gatewayHost ? (import ./gateway-cluster.nix { inherit hosts; }).primaryHost,
      dnsExpectedAddress ? (import ./gateway-cluster.nix { inherit hosts; }).clientAddress,
      serviceDomain ? head serviceDomains,
      serviceDomains ? [ serviceDomain ],
    }:
    let
      hostNames = sort (left: right: left < right) (attrNames hosts);
      exposureHostNames = filter (name: builtins.pathExists (hostExposurePath name)) hostNames;
      hostExposures = map (
        name:
        loadHostExposure {
          inherit
            gatewayHost
            hosts
            name
            serviceDomain
            serviceDomains
            ;
        }
      ) exposureHostNames;
      allGroups = sortGroups (concatMap (exposure: exposure.groups or [ ]) hostExposures);
      groupNames = unique (map (group: group.name) allGroups);
      groups = map (
        name:
        let
          matching = filter (group: group.name == name) allGroups;
          first = head matching;
        in
        {
          inherit name;
          order = first.order or 1000;
          columns = first.columns or 4;
          style = first.style or "row";
          services = concatMap (group: group.services or [ ]) matching;
        }
      ) groupNames;
      homepageGroups = filter (
        group: any (service: (service.homepage or null) != null) group.services
      ) groups;
      serviceEntries = concatMap (
        group: map (service: service // { group = group.name; }) group.services
      ) groups;
      routeServices = filter (service: (service.route or null) != null) serviceEntries;
      authServices = filter (
        service: (service.route or null) != null && (serviceAuth service).mode != "none"
      ) serviceEntries;
      tcpRouteServices = filter (service: (service.tcpRoute or null) != null) serviceEntries;
      udpRouteServices = filter (service: (service.udpRoute or null) != null) serviceEntries;
      homepageRouteHosts =
        let
          matches = filter (
            service: service.id == "homepage" && (service.route or null) != null
          ) serviceEntries;
        in
        if matches == [ ] then [ ] else (head matches).route.hosts;
      docUrls = concatMap serviceDocs serviceEntries;
      smokeRows = [
        [
          "homepage"
          "Homepage target"
          "/etc/homepage-dashboard/settings.yaml"
          "target: _blank"
          ""
        ]
        [
          "homepage"
          "Homepage layout"
          "/etc/homepage-dashboard/settings.yaml"
          "layout:"
          ""
        ]
      ]
      ++ concatMap mkHomepageGroupRows homepageGroups
      ++ concatMap (mkDnsRows dnsExpectedAddress) serviceEntries
      ++ concatMap mkHttpRows serviceEntries
      ++ concatMap mkHttpsRows serviceEntries
      ++ concatMap mkAuthentikOidcRows serviceEntries
      ++ concatMap mkTcpRows serviceEntries
      ++ concatMap mkUdpRows serviceEntries
      ++ concatMap mkHomepageRows serviceEntries;
    in
    {
      inherit groups serviceEntries;

      authentikApplications = map mkAuthentikApplication authServices;

      homepage = {
        hosts = homepageRouteHosts;
        layout = map mkHomepageLayout homepageGroups;
        serviceGroups = map mkHomepageGroup homepageGroups;
      };

      routeUrlsText = concatStringsSep "\n" (map (url: "      ${url}") docUrls);
      smokeTsv = concatStringsSep "\n" (map toTsv smokeRows) + "\n";
      traefikTcpRoutes = listToAttrs (map mkTcpRoute tcpRouteServices);
      traefikRoutes = listToAttrs (map mkRoute routeServices);
      traefikUdpRoutes = listToAttrs (map mkUdpRoute udpRouteServices);
    };
}
