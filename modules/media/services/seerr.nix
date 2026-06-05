{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  mediaLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (mediaLib) cfg appdata;
in
{
  config = mkIf cfg.enable {
    services.seerr = {
      enable = true;
      port = cfg.ports.seerr;
      configDir = "${appdata}/seerr";
    };

    systemd.services = {
      seerr = {
        after = [ "seerr-appdata-migration.service" ];
        requires = [ "seerr-appdata-migration.service" ];
        serviceConfig = {
          DynamicUser = mkForce false;
          Group = "media";
          ReadWritePaths = [ "${appdata}/seerr" ];
          StateDirectory = mkForce "";
          User = "seerr";
        };
      };

      seerr-appdata-migration = {
        description = "Migrate Jellyseerr appdata to Seerr";
        before = [ "seerr.service" ];
        path = [
          pkgs.coreutils
          pkgs.findutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
        };
        script = ''
          set -euo pipefail

          old='${appdata}/jellyseerr'
          new='${appdata}/seerr'

          install -d -m 0770 -o root -g media "$new"

          if [ -d "$old" ]; then
            if find "$new" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
              echo "$new already contains data; leaving $old in place"
            else
              find "$old" -mindepth 1 -maxdepth 1 -exec mv -t "$new" -- {} +
              rmdir "$old" 2>/dev/null || true
            fi
          fi

          chown -R seerr:media "$new"
          chmod 0770 "$new"
        '';
      };
    };
  };
}
