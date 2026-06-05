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
          pkgs.nixfmt
          pkgs.restic
          pkgs.shellcheck
          pkgs.sops
          pkgs.ssh-to-age
          pkgs.statix
        ];
      };

      formatter.${system} = pkgs.nixfmt;

      # ==========================================================================
      # COLMENA HIVE - Fleet deployment configuration
      # ==========================================================================

      legacyPackages.${system}.colmenaHive = colmenaHive;
    };
}
