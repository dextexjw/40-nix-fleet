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
 in
{
  config = mkIf cfg.enable {
services.syncthing = {
  enable = true;
  configDir = "${appdata}/syncthing/.config/syncthing";
  dataDir = "${appdata}/syncthing";
  guiAddress = "0.0.0.0:${toString cfg.ports.syncthing}";
  guiPasswordFile = secretPath "syncthing-gui-password";
  openDefaultPorts = true;
  overrideDevices = false;
  overrideFolders = false;
  settings = {
    gui = {
      user = "smoke";
      theme = "black";
    };
    options.urAccepted = -1;
  };
};
  };
}
