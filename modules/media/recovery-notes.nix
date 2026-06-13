{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  mediaLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (mediaLib)
    cfg
    appdata
    mediaGluetunRouteUrls
    mediaRoot
    resticPasswordFile
    ;
in
{
  config = mkIf cfg.enable {
    environment.etc."fleet/media-vm.md".text = ''
      media-vm restore model
      ======================

      Restore /srv/appsdata after reinstalling this NixOS host, before first
      use of Jellyfin, Audiobookshelf, Kavita, BookOrbit, ARR apps,
      qBittorrent, Gluetun, SABnzbd, or Seerr. The first activation creates
      /run/secrets/restic-password, /mnt/backups, Restic, users/groups, and
      service units needed for restore.

      Media files under /mnt/media are mounted from SMB and are not included in
      appsdata-backup.service.

      qBittorrent and SABnzbd write incomplete downloads to
      /var/lib/media-downloads on the local VM. Completed torrent and Usenet
      downloads are moved to /mnt/media/downloads. The local incomplete download
      directory is outside /srv/appsdata and is not included in Restic appdata
      backups.

      Seerr uses /srv/appsdata/seerr. On deploy or restore, legacy
      /srv/appsdata/jellyseerr data is moved there when the new path is empty.

      BookOrbit uses /srv/appsdata/bookorbit/data for application state,
      /srv/appsdata/bookorbit/postgresql for PostgreSQL 16 plus pgvector data,
      and /srv/appsdata/bookorbit/postgresql-dumps/latest.sql.gz for the
      pre-Restic PostgreSQL dump. The NAS-backed /mnt/media share is mounted
      into the container as /media and is not included in Restic appdata
      backups. Books are available at /media/Books inside BookOrbit.

      qBittorrent and SABnzbd run as podman-media-qbittorrent.service and
      podman-media-sabnzbd.service in the media-gluetun container network
      namespace. They have no host-published ports of their own;
      podman-media-gluetun.service publishes qBittorrent WebUI on
      10.2.20.113:8080, SABnzbd on 10.2.20.113:8085, and Gluetun WebUI on
      10.2.20.113:3001. If Gluetun is offline, qBittorrent and SABnzbd
      networking are unavailable. Gluetun state is stored in
      /srv/appsdata/gluetun and is included in appsdata backups.

      Backup repository:
        /mnt/backups/restic/appdata/media-stack-vm

      Password file:
        /run/secrets/restic-password

      Non-destructive validation:
        mount /mnt/backups
        systemctl start appsdata-backup.service
        systemctl start appsdata-restore-check.service
        systemctl status bookorbit-declarative-config.service
        systemctl is-active postgresql.service
        systemctl is-active podman-media-bookorbit.service
        systemctl is-active podman-media-gluetun.service
        systemctl is-active podman-media-qbittorrent.service
        systemctl is-active podman-media-sabnzbd.service
        systemctl is-active podman-media-gluetun-webui.service
        systemctl status appsdata-backup.service appsdata-restore-check.service

      Restore test target:
        /var/tmp/appsdata-restore-check

      Bootstrap restore outline:
        1. Deploy media-vm once.
        2. Before opening app web UIs, run this from the repo development shell:
             scripts/media-vm/restore-media-appdata.sh
        3. The script stops media services, mounts /mnt/backups, checks for
           media-vm/appsdata snapshots, moves fresh appdata aside, repairs
           restored ownership, reapplies tmpfiles, fixes Prowlarr DynamicUser
           ownership, and restarts media services.
        4. If multiple snapshots exist, rerun with an explicit snapshot ID:
             scripts/media-vm/restore-media-appdata.sh <snapshot-id>
        5. If no matching snapshot exists, the script starts media services and
           appsdata-backup.timer, then continues as a fresh system.

      Full restore outline:
        1. Stop appsdata-backup.timer, PostgreSQL, and media services.
        2. Mount /mnt/backups.
        3. Choose a media-vm/appsdata snapshot ID, avoiding tiny fresh-system
           snapshots made after a rebuild.
        4. Move existing /srv/appsdata aside, then restore the chosen snapshot
           to / with restic --verify.
        5. Normalize ownership for rebuilt users and run systemd-tmpfiles --create.
           Keep /srv/appsdata/prowlarr owned by nobody:nogroup with mode 0700
           so the Prowlarr DynamicUser idmapped bind mount can access SQLite.
        6. Restart media-gluetun-control-auth-config.service,
           kavita-token-key.service, PostgreSQL, media services,
           appsdata-backup.timer, and appsdata-restore-check.service.

      BookOrbit declarative app setup:
        Direct URL: http://10.2.20.113:3000
        Gateway URLs: https://bookorbit.jax22.com and http://bookorbit.h
        Local superuser: coldkey
        Local superuser email: coldkey@jax22.com
        Local superuser password: /run/secrets/bookorbit-admin-password
        OIDC issuer URI: https://auth.jax22.com/application/o/bookorbit/
        OIDC client ID: bookorbit
        OIDC client secret: /run/secrets/bookorbit-oidc-client-secret
        OIDC scopes: openid profile email groups
        OIDC provider slug: authentik
        bookorbit-declarative-config.service keeps the local superuser and
        Authentik OIDC provider present, with local account linking and
        auto-provisioning enabled.

      Jellyfin kids access is configured inside Jellyfin after first setup:
      create a non-admin user named kids, grant only the Kids Movies and Kids TV
      Shows libraries, disable deletion and downloads, then optionally use
      parental controls or a kids-approved tag for an extra guardrail.

      First-run setup is available at http://10.2.20.113:8096/web/index.html#!/wizardstart.html.
      Complete it in a browser before connecting native Jellyfin clients.
      Audiobookshelf is available at http://10.2.20.113:8000, Kavita is
      available at http://10.2.20.113:5000, qBittorrent is available through
      MediaVM Gluetun at http://10.2.20.113:8080, SABnzbd is available through
      MediaVM Gluetun at http://10.2.20.113:8085, and the MediaVM Gluetun WebUI
      is available at http://10.2.20.113:3001 and, through Gateway Traefik,
      ${concatStringsSep " and " mediaGluetunRouteUrls}. BookOrbit is available
      at http://10.2.20.113:3000, https://bookorbit.jax22.com, and
      http://bookorbit.h.
    '';
  };
}
