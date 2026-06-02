{ lib, root ? ../. }:

with lib;

let
  hostExposurePath = name: root + "/hosts/${name}/exposure.nix";

  loadHostExposure =
    {
      hosts,
      serviceDomain,
      name,
    }:
    import (hostExposurePath name) {
      inherit hosts lib serviceDomain;
    };

  sortGroups = sort (
    left: right:
    if (left.order or 1000) == (right.order or 1000) then
      left.name < right.name
    else
      (left.order or 1000) < (right.order or 1000)
  );

  primaryRouteHost = route: head route.hosts;

  mkCommand =
    http: hostName:
    let
      path = http.path or "/";
      curl = if http.discard or false then "curl -fsS -o /dev/null" else "curl -fsS";
    in
    http.command or "${curl} -H 'Host: ${hostName}' http://127.0.0.1${path} >/dev/null";

  routeDefaultDocs =
    service:
    let
      route = service.route or null;
    in
    optionals (route != null) (map (host: "http://${host}") route.hosts);

  serviceDocs =
    service:
    if service ? docs && service.docs ? urls then
      service.docs.urls
    else
      routeDefaultDocs service;

  mkRoute =
    service:
    nameValuePair service.id {
      inherit (service.route) description hosts url;
    };

  mkHomepageService =
    service:
    let
      homepage = service.homepage;
      route = service.route or null;
    in
    {
      inherit (service) name;
      description =
        homepage.description or (
          if route == null then
            ""
          else
            route.description
        );
      inherit (homepage) href;
      icon = homepage.icon or null;
      siteMonitor = homepage.siteMonitor or null;
    };

  mkHomepageGroup = group: {
    inherit (group) name;
    services = map mkHomepageService (filter (service: (service.homepage or null) != null) group.services);
  };

  mkHomepageLayout = group: {
    ${group.name} = {
      columns = group.columns or 4;
      style = group.style or "row";
    };
  };

  mkDnsRows =
    gatewayHost: service:
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
      expected = smoke.dnsExpected or gatewayHost.ip;
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
      canonicalHost =
        if route == null then
          null
        else
          primaryRouteHost route;
      hostNames =
        if http == null then
          [ ]
        else if http ? host then
          [ http.host ]
        else if route != null then
          route.hosts
        else
          [ ];
      requiredUnit = (http.requiredUnit or (smoke.requiredUnit or ""));
    in
    optionals (http != null && (http.enable or true)) (
      map (
        hostName:
        [
          "http"
          (
            http.description or (
              "${service.name} route"
              + optionalString (canonicalHost != null && hostName != canonicalHost) " (${hostName})"
            )
          )
          (mkCommand http hostName)
          requiredUnit
        ]
      ) hostNames
    );

  mkHomepageRows =
    service:
    let
      homepage = service.homepage or null;
      smoke = service.smoke or { };
      requiredUnit = smoke.requiredUnit or "";
    in
    optionals (homepage != null) (
      [
        [
          "homepage"
          "${service.name} href"
          "/etc/homepage-dashboard/services.yaml"
          homepage.href
          requiredUnit
        ]
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

  toTsv = row: concatStringsSep "\t" row;
in
{
  load =
    {
      hosts,
      serviceDomain,
    }:
    let
      gatewayHost = hosts.gateway-vm;
      hostNames = sort (left: right: left < right) (attrNames hosts);
      exposureHostNames = filter (name: builtins.pathExists (hostExposurePath name)) hostNames;
      hostExposures = map (
        name:
        loadHostExposure {
          inherit hosts name serviceDomain;
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
      homepageGroups = filter (group: any (service: (service.homepage or null) != null) group.services) groups;
      serviceEntries = concatMap (
        group: map (service: service // { group = group.name; }) group.services
      ) groups;
      routeServices = filter (service: (service.route or null) != null) serviceEntries;
      homepageRouteHosts =
        let
          matches = filter (service: service.id == "homepage" && (service.route or null) != null) serviceEntries;
        in
        if matches == [ ] then
          [ ]
        else
          (head matches).route.hosts;
      docUrls = concatMap serviceDocs serviceEntries;
      smokeRows =
        [
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
        ++ concatMap (mkDnsRows gatewayHost) serviceEntries
        ++ concatMap mkHttpRows serviceEntries
        ++ concatMap mkHomepageRows serviceEntries;
    in
    {
      inherit groups serviceEntries;

      homepage = {
        hosts = homepageRouteHosts;
        layout = map mkHomepageLayout homepageGroups;
        serviceGroups = map mkHomepageGroup homepageGroups;
      };

      routeUrlsText = concatStringsSep "\n" (map (url: "      ${url}") docUrls);
      smokeTsv = concatStringsSep "\n" (map toTsv smokeRows) + "\n";
      traefikRoutes = listToAttrs (map mkRoute routeServices);
    };
}
