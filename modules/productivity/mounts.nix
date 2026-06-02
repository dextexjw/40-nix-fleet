{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg smbCredentialsFile systemdMountOptions;
 in
{
  config = mkIf cfg.enable {
systemd.automounts = [
  {
    where = toString cfg.smb.backupMount;
    wantedBy = [ "multi-user.target" ];
    automountConfig.TimeoutIdleSec = "60s";
  }
];

systemd.mounts = [
  {
    description = "Backup SMB share";
    what = cfg.smb.backupDevice;
    where = toString cfg.smb.backupMount;
    type = "cifs";
    options = concatStringsSep "," (
      systemdMountOptions
      ++ [
        "credentials=${smbCredentialsFile}"
        "dir_mode=0750"
        "file_mode=0640"
        "forcegid"
        "gid=productivity"
      ]
    );
    after = [ "network-online.target" ];
    before = [ "umount.target" ];
    conflicts = [ "umount.target" ];
    requires = [ "network-online.target" ];
    unitConfig.DefaultDependencies = false;
    mountConfig.TimeoutSec = "30s";
  }
];
  };
}
