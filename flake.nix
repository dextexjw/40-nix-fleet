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

      mkLifecycleConsumer =
        _: node:
        let
          config = node.config;
          applications = lib.attrByPath [ "fleet" "gateway" "authentik" "applications" ] { } config;
          dnsHosts = lib.attrByPath [ "networking" "hosts" gatewayCluster.clientAddress ] [ ] config;
          homepageGroups = lib.attrByPath [ "fleet" "gateway" "homepage" "serviceGroups" ] [ ] config;
          monitoringTarget = lib.attrByPath [
            "environment"
            "etc"
            "fleet/checkmate-targets.json"
          ] null config;
          routes = lib.attrByPath [ "fleet" "gateway" "traefik" "routes" ] { } config;
          routeHosts = lib.concatMap (route: route.hosts or [ ]) (builtins.attrValues routes);
          smokeTarget = lib.attrByPath [ "environment" "etc" "fleet/gateway-exposure-smoke.tsv" ] null config;
          technitiumEnabled = lib.attrByPath [ "services" "technitium-dns-server" "enable" ] false config;
          rendered = {
            authentication = applications != { };
            dns = technitiumEnabled || dnsHosts != [ ];
            firewall = routes != { } && lib.attrByPath [ "networking" "firewall" "enable" ] false config;
            homepage = homepageGroups != [ ];
            monitoring = monitoringTarget != null;
            route = routes != { };
            smoke = smokeTarget != null;
            tls = builtins.any (lib.hasSuffix ".${serviceDomains.primary}") routeHosts;
          };
          artifacts = {
            authentication = applications;
            dns = {
              hosts = dnsHosts;
              technitium = technitiumEnabled;
            };
            firewall = {
              enable = config.networking.firewall.enable;
              inherit routes;
            };
            homepage = homepageGroups;
            monitoring = if monitoringTarget == null then null else builtins.toString monitoringTarget.source;
            route = routes;
            smoke = if smokeTarget == null then null else smokeTarget.text;
            tls = builtins.filter (lib.hasSuffix ".${serviceDomains.primary}") routeHosts;
          };
          evidence = lib.mapAttrs (
            surface: enabled:
            if enabled then builtins.hashString "sha256" (builtins.toJSON artifacts.${surface}) else null
          ) rendered;
        in
        {
          inherit evidence rendered;
          consumerSurfaces = builtins.attrNames (lib.filterAttrs (_: enabled: enabled) rendered);
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
