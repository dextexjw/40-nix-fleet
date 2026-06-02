{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.monitoring.agents;

  capturePackage = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "checkmate-capture";
    version = "1.4.0";

    src = pkgs.fetchurl {
      url = "https://github.com/bluewave-labs/capture/releases/download/v${version}/capture_${version}_linux_amd64.tar.gz";
      hash = "sha256-zD+FVo5xQ4yy6tRJzBEHO/zqFK7Xnr0JWwHc8Op/DVs=";
    };

    unpackPhase = ''
      runHook preUnpack

      tar -xzf "$src"

      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      install -Dm0755 capture "$out/bin/capture"

      runHook postInstall
    '';

    meta = {
      description = "Capture hardware monitoring agent for Checkmate";
      homepage = "https://github.com/bluewave-labs/capture";
      license = lib.licenses.agpl3Only;
      mainProgram = "capture";
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.monitoring.agents = {
    enable = mkEnableOption "fleet monitoring agents";

    beszel = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Beszel agent.";
      };

      hubUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional Beszel hub URL for universal-token registration.";
      };

      keyFile = mkOption {
        type = types.path;
        default = "/run/secrets/beszel-agent-key";
        description = "Runtime file containing the Beszel hub public key.";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional runtime file containing the Beszel universal token.";
      };

      port = mkOption {
        type = types.port;
        default = 45876;
        description = "Beszel agent listener port.";
      };
    };

    checkmate.capture = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Checkmate Capture agent.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/checkmate-capture-environment";
        description = "Runtime environment file containing API_SECRET.";
      };

      package = mkOption {
        type = types.package;
        default = capturePackage;
        description = "Capture agent package.";
      };

      port = mkOption {
        type = types.port;
        default = 59232;
        description = "Capture agent listener port.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    services.beszel.agent = mkIf cfg.beszel.enable {
      enable = true;
      environment = {
        KEY_FILE = toString cfg.beszel.keyFile;
        PORT = toString cfg.beszel.port;
      }
      // optionalAttrs (cfg.beszel.hubUrl != null) {
        HUB_URL = cfg.beszel.hubUrl;
      }
      // optionalAttrs (cfg.beszel.tokenFile != null) {
        TOKEN_FILE = toString cfg.beszel.tokenFile;
      };
      openFirewall = true;
      smartmon.enable = true;
      smartmon.deviceAllow = [
        "/dev/sda"
        "/dev/sdb"
        "/dev/nvme0"
      ];
    };

    systemd.services.checkmate-capture = mkIf cfg.checkmate.capture.enable {
      description = "Checkmate Capture hardware monitoring agent";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        GIN_MODE = "release";
        PORT = toString cfg.checkmate.capture.port;
      };
      path = [
        pkgs.coreutils
        pkgs.smartmontools
      ];
      serviceConfig = {
        AmbientCapabilities = [
          "CAP_SYS_ADMIN"
          "CAP_SYS_RAWIO"
        ];
        CapabilityBoundingSet = [
          "CAP_SYS_ADMIN"
          "CAP_SYS_RAWIO"
        ];
        DeviceAllow = [
          "/dev/sda r"
          "/dev/sdb r"
          "/dev/nvme0 r"
        ];
        EnvironmentFile = cfg.checkmate.capture.environmentFile;
        ExecStart = "${cfg.checkmate.capture.package}/bin/capture";
        LockPersonality = true;
        NoNewPrivileges = false;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectHome = "read-only";
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RestartSec = "30s";
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        Type = "simple";
        UMask = "0027";
      };
    };

    networking.firewall.allowedTCPPorts = [
      cfg.beszel.port
      cfg.checkmate.capture.port
    ];
  };
}
