{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  testbedLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg smbCredentialsFile systemdMountOptions;
in
{
  config = mkIf cfg.enable {
    systemd.automounts = [
      {
        where = toString cfg.smb.backupMount;
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "60s";
      }
      {
        where = toString cfg.smb.mediaMount;
        wantedBy = [ "multi-user.target" ];
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
            "gid=testbed"
          ]
        );
        after = [ "network-online.target" ];
        before = [ "umount.target" ];
        conflicts = [ "umount.target" ];
        requires = [ "network-online.target" ];
        unitConfig.DefaultDependencies = false;
        mountConfig.TimeoutSec = "30s";
      }
      {
        description = "Media SMB share";
        what = cfg.smb.mediaDevice;
        where = toString cfg.smb.mediaMount;
        type = "cifs";
        options = concatStringsSep "," (
          systemdMountOptions
          ++ [
            "credentials=${smbCredentialsFile}"
            "dir_mode=0775"
            "file_mode=0664"
            "forcegid"
            "forceuid"
            "gid=testbed"
            "uid=1000"
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
