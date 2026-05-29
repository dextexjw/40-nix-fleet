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

      # For scaling up your homelab, you'd likely want automated host generation:
      # mkHost = name: hostConfig: {
      #   deployment = {
      #     targetHost = hostConfig.ip;
      #     targetUser = hostConfig.user;
      #     tags = hostConfig.tags;
      #   };
      #   imports = [ ./hosts/${name}/configuration.nix ];
      # };
      # hostConfigs = builtins.mapAttrs mkHost hosts;

      colmenaHive = colmena.lib.makeHive {
        # ========================================================================
        # GLOBAL CONFIGURATION - Settings applied to all hosts
        # ========================================================================

        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ ];
          };
        };

        # ========================================================================
        # HOST DEFINITIONS - Individual server configurations
        # ========================================================================

        gateway-vm = {
          deployment = {
            sshOptions = ephemeralSshOptions;
            targetHost = hosts.gateway-vm.ip;
            targetUser = hosts.gateway-vm.user;
            tags = hosts.gateway-vm.tags;
          };

          imports = [
            sops-nix.nixosModules.sops
            ./hosts/gateway-vm/configuration.nix
          ];
        };

        media-vm = {
          deployment = {
            sshOptions = ephemeralSshOptions;
            targetHost = hosts.media-vm.ip;
            targetUser = hosts.media-vm.user;
            tags = hosts.media-vm.tags;
          };

          imports = [
            sops-nix.nixosModules.sops
            ./hosts/media-vm/configuration.nix
          ];
        };

        productivity-vm = {
          deployment = {
            sshOptions = ephemeralSshOptions;
            targetHost = hosts.productivity-vm.ip;
            targetUser = hosts.productivity-vm.user;
            tags = hosts.productivity-vm.tags;
          };

          imports = [
            sops-nix.nixosModules.sops
            ./hosts/productivity-vm/configuration.nix
          ];
        };
      };
    in
    {
      # ==========================================================================
      # DEVELOPMENT SHELL - Local development environment
      # ==========================================================================

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          colmena.packages.${system}.colmena
          pkgs.age
          pkgs.restic
          pkgs.sops
          pkgs.ssh-to-age
        ];
      };

      # ==========================================================================
      # COLMENA HIVE - Fleet deployment configuration
      # ==========================================================================

      legacyPackages.${system}.colmenaHive = colmenaHive;
    };
}
