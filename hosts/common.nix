{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fleet.host;
  hosts = import ../hosts.nix;
in
{
  imports = [
    ../modules/monitoring/agents.nix
    ../modules/monitoring/node-exporter.nix
  ];

  options.fleet.host = {
    name = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrNames hosts));
      default = null;
      description = "Fleet inventory host name used for shared VM plumbing.";
    };

    stateVersion = lib.mkOption {
      type = lib.types.str;
      default = "25.11";
      description = "NixOS stateVersion for this VM.";
    };
  };

  config = lib.mkMerge [
    {
      # ============================================================================
      # NIX CONFIGURATION
      # ============================================================================

      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          auto-optimise-store = true;
          trusted-users = [
            "@wheel"
            "smoke"
          ];
        };
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 30d";
        };
      };

      nixpkgs.config.allowUnfree = true;

      # ============================================================================
      # USER MANAGEMENT
      # ============================================================================

      users.users.smoke = {
        isNormalUser = true;
        description = "Smoke";
        extraGroups = [
          "networkmanager"
          "wheel"
        ];

        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIATd/kn93HeAqaT5e8uW68n/JoWBesQkyruVNLsG3NDc khalid"
        ];
      };

      # ============================================================================
      # SECURITY
      # ============================================================================

      security.sudo.wheelNeedsPassword = false;

      # ============================================================================
      # NETWORKING
      # ============================================================================

      networking.networkmanager.enable = true;
      networking.firewall.enable = true;
      networking.firewall.allowedTCPPorts = [ 22 ]; # SSH

      # ============================================================================
      # SERVICES
      # ============================================================================

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
        };
      };

      # --------------------------------------------------------------------------
      # MONITORING
      # --------------------------------------------------------------------------

      fleet.monitoring.nodeExporter.enable = true;
      fleet.monitoring.agents = {
        enable = true;
        beszel = {
          keyFile = "/run/secrets/beszel-agent-key";
        };
        checkmate.capture.environmentFile = "/run/secrets/checkmate-capture-environment";
      };

      # ============================================================================
      # PACKAGES
      # ============================================================================

      environment.systemPackages = with pkgs; [
        bat
        btop
        curl
        eza
        fd
        fzf
        git
        iperf3
        jq
        just
        lazygit
        mosh
        mtr
        ncdu
        neovim
        python3
        ripgrep
        rsync
        tmux
        wget
        yq
        zellij
      ];

      programs.direnv.enable = true;
      programs.zoxide.enable = true;

      # ============================================================================
      # LOCALIZATION & TIMEZONE
      # ============================================================================

      time.timeZone = "America/New_York";

      i18n.defaultLocale = "en_US.UTF-8";
      i18n.extraLocaleSettings = {
        LC_ADDRESS = "en_US.UTF-8";
        LC_IDENTIFICATION = "en_US.UTF-8";
        LC_MEASUREMENT = "en_US.UTF-8";
        LC_MONETARY = "en_US.UTF-8";
        LC_NAME = "en_US.UTF-8";
        LC_NUMERIC = "en_US.UTF-8";
        LC_PAPER = "en_US.UTF-8";
        LC_TELEPHONE = "en_US.UTF-8";
        LC_TIME = "en_US.UTF-8";
      };

      # ============================================================================
      # INPUT & KEYBOARD
      # ============================================================================

      services.xserver.xkb = {
        layout = "us";
        variant = "";
      };
    }

    (lib.mkIf (cfg.name != null) (
      let
        host = hosts.${cfg.name};
      in
      {
        networking.hostName = cfg.name;
        networking.domain = host.domain;

        networking.networkmanager.enable = lib.mkForce false;
        networking.useDHCP = lib.mkForce false;
        systemd.network = {
          enable = true;
          networks."10-lan" = {
            matchConfig.Name = [
              "en*"
              "eth*"
            ];
            networkConfig = {
              Address = "${host.ip}/24";
              DNS = host.nameservers;
              DNSDefaultRoute = true;
              Domains = [
                host.domain
                "~${host.domain}"
              ];
              Gateway = host.gateway;
            };
          };
        };

        boot.loader.grub.enable = true;
        boot.loader.grub.device = host.vm.disk;
        boot.loader.grub.useOSProber = true;

        time.timeZone = host.timezone;
        system.stateVersion = cfg.stateVersion;
      }
    ))
  ];
}
