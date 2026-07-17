{
  # ============================================================================
  # FLAKE INPUTS - External dependencies and packages
  # ============================================================================

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  # ============================================================================
  # FLAKE OUTPUTS - What this flake provides
  # ============================================================================

  outputs =
    {
      nixpkgs,
      colmena,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";

      # Import host definitions from single source of truth
      hosts = import ./hosts.nix;
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};

      ephemeralSshOptions = [
        "-o"
        "CheckHostIP=no"
        "-o"
        "GlobalKnownHostsFile=/dev/null"
        "-o"
        "LogLevel=ERROR"
        "-o"
        "StrictHostKeyChecking=no"
        "-o"
        "UpdateHostKeys=no"
        "-o"
        "UserKnownHostsFile=/dev/null"
      ];

      hostConfigurationPath = name: ./hosts + "/${name}/configuration.nix";

      deployedHosts = lib.filterAttrs (name: _: builtins.pathExists (hostConfigurationPath name)) hosts;

      mkHost = name: hostConfig: {
        deployment = {
          sshOptions = ephemeralSshOptions;
          targetHost = hostConfig.ip;
          targetUser = hostConfig.user;
          tags = hostConfig.tags;
        };

        imports = [
          { _module.args.fleetHostName = name; }
          sops-nix.nixosModules.sops
          (hostConfigurationPath name)
        ];
      };

      hostConfigs = lib.mapAttrs mkHost deployedHosts;

      colmenaHive = colmena.lib.makeHive (
        {
          # ========================================================================
          # GLOBAL CONFIGURATION - Settings applied to all hosts
          # ========================================================================

          meta = {
            nixpkgs = import nixpkgs {
              system = "x86_64-linux";
              overlays = [ ];
            };
          };
        }
        // hostConfigs
      );

      gatewayCluster = import ./lib/gateway-cluster.nix { inherit hosts; };
      serviceDomains = import ./lib/service-domains.nix;
      exposure = import ./lib/exposure.nix {
        inherit lib;
        root = ./.;
      };

      mkLifecycleConsumer =
        name: node:
        let
          config = node.config;
          expectedCatalog = exposure.load {
            gatewayHost = hosts.${name};
            dnsExpectedAddress = gatewayCluster.clientAddress;
            inherit hosts;
            serviceDomain = serviceDomains.primary;
            serviceDomains = serviceDomains.all;
          };
          expectedApplications = expectedCatalog.authentikApplications;
          expectedHomepageGroups = expectedCatalog.homepage.serviceGroups;
          expectedRoutes = expectedCatalog.traefikRoutes;
          expectedTcpRoutes = expectedCatalog.traefikTcpRoutes;
          expectedUdpRoutes = expectedCatalog.traefikUdpRoutes;
          expectedRouteHosts = lib.concatMap (route: route.hosts or [ ]) (builtins.attrValues expectedRoutes);
          isGateway = builtins.elem name gatewayCluster.members;
          isMonitoring = lib.attrByPath [
            "fleet"
            "monitoring"
            "checkmateProvisioning"
            "enable"
          ] false config;
          expectedMonitorServices = builtins.filter (
            service: service ? route && !(service ? checkmate && (service.checkmate.enable or true) == false)
          ) expectedCatalog.serviceEntries;
          expectedPlatformRouteServices =
            if isMonitoring then
              expectedMonitorServices
            else
              builtins.filter (service: service ? route) expectedCatalog.serviceEntries;
          expectedPlatformDnsHosts = lib.unique (
            lib.concatMap (service: service.route.hosts) expectedPlatformRouteServices
          );
          expectedGatewayDnsHosts = lib.unique (
            lib.concatMap (
              service:
              let
                route = service.route or null;
                smoke = service.smoke or { };
              in
              if smoke ? dnsHosts then
                smoke.dnsHosts
              else if (smoke.dns or (route != null)) && route != null then
                route.hosts
              else
                [ ]
            ) expectedCatalog.serviceEntries
          );
          applications = lib.attrByPath [ "fleet" "gateway" "authentik" "applications" ] [ ] config;
          dnsHosts = lib.attrByPath [ "networking" "hosts" gatewayCluster.clientAddress ] [ ] config;
          homepageGroups = lib.attrByPath [ "fleet" "gateway" "homepage" "serviceGroups" ] [ ] config;
          monitoringTarget = lib.attrByPath [
            "environment"
            "etc"
            "fleet/checkmate-targets.json"
          ] null config;
          routes = lib.attrByPath [ "fleet" "gateway" "traefik" "routes" ] { } config;
          tcpRoutes = lib.attrByPath [ "fleet" "gateway" "traefik" "tcpRoutes" ] { } config;
          udpRoutes = lib.attrByPath [ "fleet" "gateway" "traefik" "udpRoutes" ] { } config;
          routeHosts = lib.concatMap (route: route.hosts or [ ]) (builtins.attrValues routes);
          routesMatch =
            builtins.attrNames routes == builtins.attrNames expectedRoutes
            && builtins.all (
              routeName:
              routes.${routeName}.hosts == expectedRoutes.${routeName}.hosts
              && routes.${routeName}.url == expectedRoutes.${routeName}.url
            ) (builtins.attrNames expectedRoutes);
          streamRoutesMatch = tcpRoutes == expectedTcpRoutes && udpRoutes == expectedUdpRoutes;
          allowedTcpPorts = config.networking.firewall.allowedTCPPorts;
          allowedUdpPorts = config.networking.firewall.allowedUDPPorts;
          expectedTcpPorts = [
            (lib.attrByPath [ "fleet" "gateway" "traefik" "httpPort" ] 80 config)
          ]
          ++ lib.optional tlsConfig.enable (
            lib.attrByPath [ "fleet" "gateway" "traefik" "httpsPort" ] 443 config
          )
          ++ map (route: route.port) (builtins.attrValues expectedTcpRoutes);
          expectedUdpPorts = map (route: route.port) (builtins.attrValues expectedUdpRoutes);
          tlsConfig = lib.attrByPath [ "fleet" "gateway" "traefik" "tls" ] { } config;
          certificateNames =
            if tlsConfig == { } then
              [ ]
            else
              [
                tlsConfig.domain
                "*.${tlsConfig.domain}"
              ]
              ++ tlsConfig.extraSans;
          certificateCovers =
            certificateName: hostName:
            if lib.hasPrefix "*." certificateName then
              let
                suffix = lib.removePrefix "*" certificateName;
                prefix = lib.removeSuffix suffix hostName;
              in
              lib.hasSuffix suffix hostName && prefix != hostName && builtins.match ".*[.].*" prefix == null
            else
              certificateName == hostName;
          smokeTarget = lib.attrByPath [ "environment" "etc" "fleet/gateway-exposure-smoke.tsv" ] null config;
          technitiumEnabled = lib.attrByPath [ "services" "technitium-dns-server" "enable" ] false config;
          technitiumZones = lib.attrByPath [ "fleet" "gateway" "technitium" "localZones" ] [ ] config;
          serviceMonitors =
            lib.attrByPath [ "fleet" "monitoring" "checkmateProvisioning" "serviceMonitors" ] [ ]
              config;
          zoneRecordName =
            zoneDomain: dnsHost:
            let
              zoneSuffix = ".${zoneDomain}";
            in
            if dnsHost == zoneDomain then
              "@"
            else if lib.hasSuffix zoneSuffix dnsHost then
              lib.removeSuffix zoneSuffix dnsHost
            else
              null;
          gatewayDnsMatches = builtins.all (
            dnsHost:
            builtins.any (
              zone:
              let
                recordName = zoneRecordName zone.domain dnsHost;
              in
              recordName != null
              && lib.attrByPath [ "aRecords" recordName ] null zone == gatewayCluster.clientAddress
            ) technitiumZones
          ) expectedGatewayDnsHosts;
          applicable = {
            authentication = isGateway && expectedApplications != [ ];
            dns = technitiumEnabled || dnsHosts != [ ];
            firewall = isGateway && expectedRoutes != { };
            homepage = isGateway && expectedHomepageGroups != [ ];
            monitoring = isMonitoring;
            route = isGateway && expectedRoutes != { };
            smoke = isGateway && expectedCatalog.smokeTsv != "";
            tls = isGateway && builtins.any (lib.hasSuffix ".${serviceDomains.primary}") expectedRouteHosts;
          };
          rendered = {
            authentication =
              map (application: application.slug) applications
              == map (application: application.slug) expectedApplications;
            dns =
              !applicable.dns
              || (
                if isGateway then
                  technitiumEnabled && gatewayDnsMatches
                else
                  lib.sort builtins.lessThan dnsHosts == lib.sort builtins.lessThan expectedPlatformDnsHosts
              );
            firewall =
              !applicable.firewall
              || (
                routesMatch
                && streamRoutesMatch
                && lib.attrByPath [ "networking" "firewall" "enable" ] false config
                && builtins.all (port: builtins.elem port allowedTcpPorts) expectedTcpPorts
                && builtins.all (port: builtins.elem port allowedUdpPorts) expectedUdpPorts
              );
            homepage = homepageGroups == expectedHomepageGroups;
            monitoring =
              !applicable.monitoring
              || (
                monitoringTarget != null
                && map (monitor: monitor.id) serviceMonitors == map (service: service.id) expectedMonitorServices
              );
            route = routesMatch && streamRoutesMatch;
            smoke = !applicable.smoke || (smokeTarget != null && smokeTarget.text == expectedCatalog.smokeTsv);
            tls =
              !applicable.tls
              || (
                tlsConfig.enable
                && tlsConfig.domain == serviceDomains.primary
                && tlsConfig.resolver != ""
                && builtins.all (
                  hostName:
                  builtins.any (certificateName: certificateCovers certificateName hostName) certificateNames
                ) (builtins.filter (lib.hasSuffix ".${serviceDomains.primary}") expectedRouteHosts)
              );
          };
          artifacts = {
            authentication = applications;
            dns = {
              hosts = dnsHosts;
              technitium = technitiumEnabled;
              zones = technitiumZones;
            };
            firewall = {
              enable = config.networking.firewall.enable;
              inherit allowedTcpPorts allowedUdpPorts;
              inherit routes;
              inherit tcpRoutes udpRoutes;
            };
            homepage = homepageGroups;
            monitoring = {
              source = if monitoringTarget == null then null else builtins.toString monitoringTarget.source;
              inherit serviceMonitors;
            };
            route = {
              http = routes;
              tcp = tcpRoutes;
              udp = udpRoutes;
            };
            smoke = if smokeTarget == null then null else smokeTarget.text;
            tls = {
              inherit certificateNames;
              config = tlsConfig;
              hosts = builtins.filter (lib.hasSuffix ".${serviceDomains.primary}") routeHosts;
            };
          };
          evidence = lib.mapAttrs (
            surface: isApplicable:
            if isApplicable then builtins.hashString "sha256" (builtins.toJSON artifacts.${surface}) else null
          ) applicable;
        in
        {
          inherit evidence rendered;
          consumerSurfaces = builtins.attrNames (lib.filterAttrs (_: isApplicable: isApplicable) applicable);
        };

      fleetLifecycleConsumers = lib.mapAttrs mkLifecycleConsumer colmenaHive.nodes;
    in
    {
      # ==========================================================================
      # DEVELOPMENT SHELL - Local development environment
      # ==========================================================================

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          colmena.packages.${system}.colmena
          pkgs.age
          pkgs.deadnix
          pkgs.dnsutils
          pkgs.nixfmt
          pkgs.python3
          pkgs.restic
          pkgs.ripgrep
          pkgs.shellcheck
          pkgs.sops
          pkgs.ssh-to-age
          pkgs.statix
        ];
      };

      formatter.${system} = pkgs.nixfmt;

      checks.${system} = {
        fleet-agent-skill = pkgs.runCommand "fleet-agent-skill-check" { } ''
          ${pkgs.python3}/bin/python3 \
            ${./tests/validate-fleet-agent-skill.py} \
            ${./.agents/skills/operate-40-nix-fleet} \
            ${./.}
          touch "$out"
        '';

        fleet-lifecycle =
          pkgs.runCommand "fleet-lifecycle-check"
            {
              nativeBuildInputs = [ pkgs.gitMinimal ];
            }
            ''
              export FLEET_LIFECYCLE_COMMAND=${./scripts/fleet-lifecycle.py}
              ${pkgs.python3}/bin/python3 ${./tests/test-fleet-lifecycle.py}
              ${pkgs.python3}/bin/python3 ${./tests/test-fleet-upgrade-lifecycle.py}
              touch "$out"
            '';

        fleet-lifecycle-consumers = import ./tests/fleet-lifecycle-consumers.nix {
          consumers = fleetLifecycleConsumers;
          inherit pkgs;
        };

        testbed-recovery-lifecycle = import ./tests/testbed-recovery-lifecycle.nix {
          inherit nixpkgs pkgs system;
        };
      };

      # ==========================================================================
      # COLMENA HIVE - Fleet deployment configuration
      # ==========================================================================

      legacyPackages.${system}.colmenaHive = colmenaHive;

      inherit fleetLifecycleConsumers;
    };
}
