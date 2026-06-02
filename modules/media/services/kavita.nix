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
  inherit (mediaLib) cfg appdata mediaRoot;
 in
{
  config = mkIf cfg.enable {
services.kavita = {
  enable = true;
  dataDir = "${appdata}/kavita";
  tokenKeyFile = "${appdata}/kavita/config/token.key";
  settings = {
    IpAddresses = "0.0.0.0";
    Port = cfg.ports.kavita;
  };
};

systemd.services = {
  kavita.requires = [
    "kavita-token-key.service"
    "${utils.escapeSystemdPath mediaRoot}.mount"
  ];
  kavita.after = [
    "kavita-token-key.service"
    "${utils.escapeSystemdPath mediaRoot}.mount"
  ];
  kavita-token-key = {
    description = "Create Kavita token key";
    before = [ "kavita.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      token_file='${appdata}/kavita/config/token.key'
      install -d -m 0750 -o kavita -g kavita "$(dirname "$token_file")"

      if [ ! -s "$token_file" ]; then
        tmp="$(mktemp "''${token_file}.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        head -c 64 /dev/urandom | base64 --wrap=0 > "$tmp"
        chown kavita:kavita "$tmp"
        chmod 0600 "$tmp"
        mv "$tmp" "$token_file"
        trap - EXIT
      fi

      chown kavita:kavita "$token_file"
      chmod 0600 "$token_file"
    '';
  };
};
  };
}
