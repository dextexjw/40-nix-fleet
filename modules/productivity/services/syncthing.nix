{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg appdata secretPath;
  syncthingConfigDir = "${appdata}/syncthing/.config/syncthing";
  syncthingGuiUsername = pkgs.writeShellScript "syncthing-gui-username" ''
        set -euo pipefail

    IFS= read -r gui_user < ${secretPath "syncthing-gui-username"} || [ -n "$gui_user" ]
        test -n "$gui_user"

        config_xml=${escapeShellArg "${syncthingConfigDir}/config.xml"}
        api_key=""
        for attempt in $(seq 1 60); do
          if [ -r "$config_xml" ]; then
            api_key="$(${lib.getExe pkgs.python3} - "$config_xml" <<'PY'
    import sys
    import xml.etree.ElementTree as ET

    root = ET.parse(sys.argv[1]).getroot()
    print(root.findtext("gui/apikey") or "")
    PY
    )"
          fi

          if [ -n "$api_key" ] && curl -fsS -H "X-API-Key: $api_key" "http://127.0.0.1:${toString cfg.ports.syncthing}/rest/system/ping" >/dev/null; then
            break
          fi
          if [ "$attempt" -eq 60 ]; then
            echo "Syncthing API did not become ready for GUI username provisioning" >&2
            exit 1
          fi
          sleep 2
        done

        export GUI_USER="$gui_user"
        payload="$(${lib.getExe pkgs.python3} - <<'PY'
    import json
    import os

    print(json.dumps({"user": os.environ["GUI_USER"]}))
    PY
    )"

        curl -fsS \
          -H "X-API-Key: $api_key" \
          -H "Content-Type: application/json" \
          -X PATCH \
          --data "$payload" \
          "http://127.0.0.1:${toString cfg.ports.syncthing}/rest/config/gui" >/dev/null

        if curl -fsS -H "X-API-Key: $api_key" "http://127.0.0.1:${toString cfg.ports.syncthing}/rest/config/restart-required" | grep -q true; then
          curl -fsS -H "X-API-Key: $api_key" -X POST "http://127.0.0.1:${toString cfg.ports.syncthing}/rest/system/restart" >/dev/null
        fi
  '';
in
{
  config = mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      configDir = syncthingConfigDir;
      dataDir = "${appdata}/syncthing";
      guiAddress = "0.0.0.0:${toString cfg.ports.syncthing}";
      guiPasswordFile = secretPath "syncthing-gui-password";
      openDefaultPorts = true;
      overrideDevices = false;
      overrideFolders = false;
      settings = {
        gui = {
          theme = "black";
        };
        options.urAccepted = -1;
      };
    };

    systemd.services.syncthing-gui-username = {
      description = "Apply SOPS-backed Syncthing GUI username";
      after = [
        "syncthing-init.service"
        "syncthing.service"
      ];
      requires = [ "syncthing.service" ];
      wants = [ "syncthing-init.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gnugrep
      ];
      restartTriggers = [ syncthingGuiUsername ];
      serviceConfig = {
        ExecStart = syncthingGuiUsername;
        RemainAfterExit = true;
        Type = "oneshot";
        User = "syncthing";
      };
    };
  };
}
