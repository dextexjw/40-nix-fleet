{
  pkgs,
  ...
}:
{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../modules/monitoring/agents.nix
    ../modules/monitoring/node-exporter.nix
  ];
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
