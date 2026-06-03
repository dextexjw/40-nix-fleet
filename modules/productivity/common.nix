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
  inherit (productivityLib)
    cfg
    appdata
    appsdataDirs
    memosGid
    memosUid
    rustfsGid
    rustfsUid
    ;
in
{
  config = mkIf cfg.enable {
    boot.supportedFilesystems.cifs = true;

    users.groups.productivity = { };
    users.groups.garage = { };
    users.groups.stirling-pdf = { };

    users.users.garage = {
      isSystemUser = true;
      group = "garage";
      home = "${appdata}/garage";
    };

    users.users.stirling-pdf = {
      isSystemUser = true;
      group = "stirling-pdf";
      home = "${appdata}/stirling-pdf";
    };

    systemd.tmpfiles.rules = (map (path: "d '${path}' 0755 root root - -") appsdataDirs) ++ [
      "d '${appdata}/firefly-iii' 0750 firefly-iii nginx - -"
      "z '${appdata}/firefly-iii' 0750 firefly-iii nginx - -"
      "d '${appdata}/forgejo' 0750 forgejo forgejo - -"
      "z '${appdata}/forgejo' 0750 forgejo forgejo - -"
      "d '${appdata}/freshrss' 0750 freshrss freshrss - -"
      "z '${appdata}/freshrss' 0750 freshrss freshrss - -"
      "d '${appdata}/garage' 0750 garage garage - -"
      "z '${appdata}/garage' 0750 garage garage - -"
      "d '${appdata}/garage/data' 0750 garage garage - -"
      "z '${appdata}/garage/data' 0750 garage garage - -"
      "d '${appdata}/garage/meta' 0750 garage garage - -"
      "z '${appdata}/garage/meta' 0750 garage garage - -"
      "d '${appdata}/garage/snapshots' 0750 garage garage - -"
      "z '${appdata}/garage/snapshots' 0750 garage garage - -"
      "d '${appdata}/gitea' 0750 gitea gitea - -"
      "z '${appdata}/gitea' 0750 gitea gitea - -"
      "d '${appdata}/mkdocs' 0775 root productivity - -"
      "z '${appdata}/mkdocs' 0775 root productivity - -"
      "d '${appdata}/mkdocs/docs' 0775 root productivity - -"
      "z '${appdata}/mkdocs/docs' 0775 root productivity - -"
      "d '${appdata}/mkdocs/site' 0775 root productivity - -"
      "z '${appdata}/mkdocs/site' 0775 root productivity - -"
      "d '${appdata}/memos' 0750 ${toString memosUid} ${toString memosGid} - -"
      "z '${appdata}/memos' 0750 ${toString memosUid} ${toString memosGid} - -"
      "d '${appdata}/memos-backups' 0750 ${toString memosUid} ${toString memosGid} - -"
      "z '${appdata}/memos-backups' 0750 ${toString memosUid} ${toString memosGid} - -"
      "d '${appdata}/nextcloud' 0750 nextcloud nextcloud - -"
      "z '${appdata}/nextcloud' 0750 nextcloud nextcloud - -"
      "d '${appdata}/ntfy' 0750 ntfy-sh ntfy-sh - -"
      "z '${appdata}/ntfy' 0750 ntfy-sh ntfy-sh - -"
      "d '${appdata}/ntfy/attachments' 0750 ntfy-sh ntfy-sh - -"
      "z '${appdata}/ntfy/attachments' 0750 ntfy-sh ntfy-sh - -"
      "d '${appdata}/paperless' 0750 paperless paperless - -"
      "z '${appdata}/paperless' 0750 paperless paperless - -"
      "d '${appdata}/paperless/consume' 0750 paperless paperless - -"
      "z '${appdata}/paperless/consume' 0750 paperless paperless - -"
      "d '${appdata}/paperless/media' 0750 paperless paperless - -"
      "z '${appdata}/paperless/media' 0750 paperless paperless - -"
      "d '${appdata}/postgresql' 0750 postgres postgres - -"
      "z '${appdata}/postgresql' 0750 postgres postgres - -"
      "d '${appdata}/postgresql/${config.services.postgresql.package.psqlSchema}' 0750 postgres postgres - -"
      "z '${appdata}/postgresql/${config.services.postgresql.package.psqlSchema}' 0750 postgres postgres - -"
      "d '${appdata}/postgresql-dumps' 0700 postgres postgres - -"
      "z '${appdata}/postgresql-dumps' 0700 postgres postgres - -"
      "d '${appdata}/privatebin' 0750 privatebin nginx - -"
      "z '${appdata}/privatebin' 0750 privatebin nginx - -"
      "d '${appdata}/rustfs' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
      "z '${appdata}/rustfs' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
      "d '${appdata}/rustfs/data' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
      "z '${appdata}/rustfs/data' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
      "d '${appdata}/searxng' 0750 searx searx - -"
      "z '${appdata}/searxng' 0750 searx searx - -"
      "d '${appdata}/shlink' 0750 root productivity - -"
      "z '${appdata}/shlink' 0750 root productivity - -"
      "d '${appdata}/stirling-pdf' 0750 stirling-pdf stirling-pdf - -"
      "z '${appdata}/stirling-pdf' 0750 stirling-pdf stirling-pdf - -"
      "d '${appdata}/syncthing' 0750 syncthing syncthing - -"
      "z '${appdata}/syncthing' 0750 syncthing syncthing - -"
      "d '${appdata}/vaultwarden' 0750 vaultwarden vaultwarden - -"
      "z '${appdata}/vaultwarden' 0750 vaultwarden vaultwarden - -"
    ];

    virtualisation.oci-containers.backend = "podman";
  };
}
