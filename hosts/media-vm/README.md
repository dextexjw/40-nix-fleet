# media-vm

`media-vm` runs the media stack, BookOrbit, Gluetun-gated qBittorrent
downloads, SMB media mounts, appdata backups, and restore checks.

Fleet inventory lives in `../../hosts.nix`. Host configuration lives in
`configuration.nix` and imports the media stack from `../../modules/media/`.

## Host Model

Important host values:

- FQDN: `media-vm.home.arpa`
- IP: `10.2.20.113`
- Gateway: `10.2.20.1`
- DNS: `10.2.20.1`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`
- VM RAM: `8 GB`
- VM CPU cores: `4`
- Media SMB share: `//nas.home.arpa/media` mounted at `/mnt/media`
- Backup SMB share: `//nas.home.arpa/backups` mounted at `/mnt/backups`

Media files live on the NAS-mounted `/mnt/media` share. Application state lives
under `/srv/appsdata`, which is the restore-critical path backed up by Restic.
Incomplete downloader files live on local VM storage at
`/var/lib/media-downloads`, outside the Restic appdata backup source.

## Service Access

| Service | URL |
| --- | --- |
| Jellyfin | `http://10.2.20.113:8096` |
| Audiobookshelf | `http://10.2.20.113:8000` |
| Kavita | `http://10.2.20.113:5000` |
| BookOrbit | `http://10.2.20.113:3000` |
| Radarr | `http://10.2.20.113:7878` |
| Sonarr | `http://10.2.20.113:8989` |
| Prowlarr | `http://10.2.20.113:9696` |
| Bazarr | `http://10.2.20.113:6767` |
| qBittorrent through MediaVM Gluetun | `http://10.2.20.113:8080` |
| MediaVM Gluetun WebUI | `http://10.2.20.113:3001` |
| SABnzbd through MediaVM Gluetun | `http://10.2.20.113:8085` |
| Seerr | `http://10.2.20.113:5055` |

FlareSolverr listens on `8191` for app integration and is not opened in the
firewall.

Traefik routes are declared on `gateway-vm` for HTTPS `jax22.com` service names
and HTTP-only `.h` aliases:

- `jellyfin.jax22.com`, `jellyfin.h`
- `audiobookshelf.jax22.com`, `audiobookshelf.h`
- `kavita.jax22.com`, `kavita.h`
- `bookorbit.jax22.com`, `bookorbit.h`
- `sonarr.jax22.com`, `sonarr.h`
- `radarr.jax22.com`, `radarr.h`
- `prowlarr.jax22.com`, `prowlarr.h`
- `bazarr.jax22.com`, `bazarr.h`
- `qbittorrent.jax22.com`, `qbittorrent.h`
- `gluetun.media.jax22.com`, `gluetun.media.h`
- `sabnzbd.jax22.com`, `sabnzbd.h`
- `seerr.jax22.com`, `seerr.h`

MediaVM Gluetun WebUI is available directly at `10.2.20.113:3001` and through
Gateway Traefik at `https://gluetun.media.jax22.com/` and
`http://gluetun.media.h/`. The Gateway Homepage card monitors
`http://10.2.20.113:3001/api/health`.

qBittorrent and SABnzbd have no host-published ports of their own.
`podman-media-gluetun` publishes `8080/tcp` for qBittorrent WebUI, `8085/tcp`
for SABnzbd, and `3001/tcp` for Gluetun WebUI. `podman-media-qbittorrent` and
`podman-media-sabnzbd` run with `--network=container:media-gluetun`, so if
MediaVM Gluetun is offline, downloader networking is unavailable.

## State and Media Paths

Appdata paths:

- `/srv/appsdata/jellyfin`
- `/srv/appsdata/audiobookshelf`
- `/srv/appsdata/kavita`
- `/srv/appsdata/bookorbit/data`
- `/srv/appsdata/bookorbit/postgresql`
- `/srv/appsdata/bookorbit/postgresql-dumps/latest.sql.gz`
- `/srv/appsdata/radarr`
- `/srv/appsdata/sonarr`
- `/srv/appsdata/prowlarr`
- `/srv/appsdata/bazarr`
- `/srv/appsdata/qbittorrent`
- `/srv/appsdata/sabnzbd`
- `/srv/appsdata/seerr`
- `/srv/appsdata/flaresolverr`
- `/srv/appsdata/gluetun`
- `/srv/appsdata/monitoring`

Seerr uses `/srv/appsdata/seerr`. The declarative service migration moves
legacy `/srv/appsdata/jellyseerr` contents there when `/srv/appsdata/seerr` is
empty, and the restore helper applies the same path normalization for older
snapshots.

Media library paths:

- Movies: `/mnt/media/MOVIES`, `/mnt/media/NewMovies`
- TV: `/mnt/media/TVshows`
- Kids: `/mnt/media/KidsMedia/KidsMovies`, `/mnt/media/KidsMedia/KidsTVshows`
- Audiobooks: `/mnt/media/Audiobooks`
- Podcasts: `/mnt/media/Podcasts`
- Books and Calibre: `/mnt/media/Books`
- Comics: `/mnt/media/Comics`
- PDFs: `/mnt/media/PDFs`
- Completed downloads: `/mnt/media/downloads`
- Incomplete downloads: `/var/lib/media-downloads`

BookOrbit runs as `podman-media-bookorbit.service` with the pinned
`ghcr.io/bookorbit/bookorbit:1.10.0` image. It listens on MediaVM port `3000`,
stores app-managed state in `/srv/appsdata/bookorbit/data`, uses native
PostgreSQL 16 with `pgvector` under `/srv/appsdata/bookorbit/postgresql`, and
mounts `/mnt/media/Books` read-write as `/books`. The Books library is
NAS-backed media data and is outside the Restic appdata source.

BookOrbit OIDC is configured in the app after first setup under Settings >
OIDC / SSO:

- Issuer URI: `https://auth.jax22.com/application/o/bookorbit/`
- Client ID: `bookorbit`
- Client secret: decrypt `bookorbit-oidc-client-secret` from SOPS
- Scopes: `openid profile email groups`
- Redirect URI already provisioned in Authentik: `https://bookorbit.jax22.com/oauth2-callback`
- Enable local account linking for existing users.

## Secrets

Required secrets:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`
- `bookorbit-postgres-password`
- `bookorbit-jwt-secret`
- `bookorbit-setup-bootstrap-token`
- `bookorbit-email-encryption-key`
- `bookorbit-migration-encryption-key`
- `qbittorrent-webui-username`
- `qbittorrent-webui-password`
- `media-gluetun-control-api-key`
- `media-gluetun-openvpn-username`
- `media-gluetun-openvpn-password`

Normal edit flow:

```sh
nix develop
sops secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

If `secrets/secrets.yaml` is missing, start from the example and encrypt it:

```sh
cp secrets/example-secrets.yaml secrets/secrets.yaml
sops --encrypt --in-place secrets/secrets.yaml
```

`media-vm` decrypts secrets using `/etc/ssh/ssh_host_ed25519_key`. After a new
VM install or host key change, capture the host recipient:

```sh
ssh smoke@10.2.20.113 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

Add the printed `age1...` recipient to `.sops.yaml`, then rekey:

```sh
sops updatekeys secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

Keep `restic-password` stable. It is the encryption key for the Restic
repository; changing it makes existing snapshots unreadable with the new value.

## Bootstrap

Use this flow after preparing a fresh `media-vm` install. The destructive
`nixos-anywhere` VM install is managed from the separate installer repo before
this fleet deployment begins.

1. Enter the dev shell and make sure `secrets/secrets.yaml` is filled and encrypted.

```sh
nix develop
```

2. Run the external `nixos-anywhere` install for `media-vm`, then confirm
   non-interactive SSH works.

```sh
ssh -o BatchMode=yes smoke@10.2.20.113 true
```

3. Run the guided post-install bootstrap.

```sh
scripts/media-vm/bootstrap-media-vm.sh run
```

The wrapper runs these phases in order:

- `check-local-readiness`: verifies local tools, encrypted secrets, `nix flake check`, and `colmena build --on media-vm`.
- `enable-vm-secret-access`: runs `scripts/media-vm/update-media-sops-recipient.sh` to add the VM SSH host key as a SOPS age recipient and rekey secrets.
- `deploy-media-vm`: runs the guarded `media-vm` deployment and normalizes the transient hostname left by the installer.
- `restore-appdata`: restores existing appdata from Restic when a matching snapshot exists.
- `verify-media-vm`: confirms hostname state and runs the backup/restore validation.

If the restore phase lists multiple matching snapshots, rerun it with the exact
snapshot ID you want to restore:

```sh
scripts/media-vm/bootstrap-media-vm.sh restore-appdata <snapshot-id>
scripts/media-vm/bootstrap-media-vm.sh verify-media-vm
```

After a rebuild, avoid tiny fresh-system snapshots and choose the last known
good appdata snapshot from before the rebuild.

The phases can also be run individually:

```sh
scripts/media-vm/bootstrap-media-vm.sh check-local-readiness
scripts/media-vm/bootstrap-media-vm.sh enable-vm-secret-access
scripts/media-vm/bootstrap-media-vm.sh deploy-media-vm
scripts/media-vm/bootstrap-media-vm.sh restore-appdata [snapshot-id]
scripts/media-vm/bootstrap-media-vm.sh verify-media-vm
```

To pass a known snapshot through the full bootstrap:

```sh
scripts/media-vm/bootstrap-media-vm.sh run --snapshot-id <snapshot-id>
```

During verification, both static and transient hostname values should report
`media-vm`.

## Upgrade

Use this flow for an already-running `media-vm`. It deploys the current repo
state only; update and review `flake.lock` separately before running it.

```sh
nix develop
scripts/media-vm/upgrade-media-vm.sh run
```

The wrapper runs these phases in order:

- `check-upgrade-readiness`: verifies dev-shell tools, encrypted secrets, non-interactive SSH, `nix flake check`, and `colmena build --on media-vm`.
- `create-pre-upgrade-backup`: starts an appdata Restic backup and lists the latest matching snapshots.
- `dry-activate-media-vm`: validates the activation plan with `colmena apply --on media-vm dry-activate`.
- `deploy-media-vm`: runs the guarded `media-vm` deployment and normalizes the transient hostname.
- `verify-media-vm`: confirms hostname state, runs backup/restore validation, checks tmpfiles declarations, and verifies key media services are active.

The upgrade workflow never restores appdata automatically. Use the restore
workflow only when recovering from a failed host or bad application state.

The phases can also be run individually:

```sh
scripts/media-vm/upgrade-media-vm.sh check-upgrade-readiness
scripts/media-vm/upgrade-media-vm.sh create-pre-upgrade-backup
scripts/media-vm/upgrade-media-vm.sh dry-activate-media-vm
scripts/media-vm/upgrade-media-vm.sh deploy-media-vm
scripts/media-vm/upgrade-media-vm.sh verify-media-vm
```

## Deploy

Use plain Colmena commands from inside `nix develop`.

```sh
colmena build --on media-vm
colmena apply --on media-vm dry-activate
colmena apply --on media-vm switch
```

The guarded deploy helper checks local SOPS decryption and confirms the VM has
a matching SOPS recipient before switching:

```sh
scripts/media-vm/deploy-media.sh
```

## Backups and Restore

`media-vm` backs up `/srv/appsdata` with Restic.

- Service: `appsdata-backup.service`
- Timer: `appsdata-backup.timer`
- Source: `/srv/appsdata`
- Repository: `/mnt/backups/restic/appdata/media-stack-vm`
- Password file: `/run/secrets/restic-password`
- Schedule: daily
- Retention: 7 daily, 4 weekly, 6 monthly snapshots
- Restic host: `media-vm`
- Restic tag: `appsdata`
- Non-destructive restore validation: `appsdata-restore-check.service`

`appsdata-backup.service` requires `bookorbit-postgresql-dump.service` first.
That service writes a compressed BookOrbit PostgreSQL dump to
`/srv/appsdata/bookorbit/postgresql-dumps/latest.sql.gz`, then Restic captures
the dump, BookOrbit app data, and PostgreSQL data directory under
`/srv/appsdata`. `/mnt/media/Books` remains NAS-backed media data outside the
Restic appdata source.

Post-deploy validation:

```sh
scripts/media-vm/test-media-backup.sh
```

That script mounts `/mnt/backups` if needed, starts a backup, starts the restore
check, verifies the timer, lists the latest tagged snapshots, checks the
PostgreSQL, BookOrbit, MediaVM Gluetun, qBittorrent, and SABnzbd units, confirms
BookOrbit, qBittorrent, SABnzbd, and Gluetun WebUI are reachable, validates the
BookOrbit PostgreSQL dump, and verifies the downloader sidecars have no
host-published ports of their own.

To run the disruptive kill-switch check after changing Gluetun or downloader
networking:

```sh
scripts/media-vm/test-media-backup.sh --include-kill-switch
```

That briefly stops `podman-media-gluetun.service`, confirms qBittorrent and
SABnzbd stop or become unreachable, confirms they cannot start while Gluetun is
runtime-masked, and then restarts the MediaVM Gluetun stack.

Manual backup inspection on `media-vm`:

```sh
systemctl status appsdata-backup.timer
journalctl -u appsdata-backup.service
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host media-vm --path /srv/appsdata --tag appsdata
```

Routine restore validation:

```sh
systemctl start appsdata-restore-check.service
journalctl -u appsdata-restore-check.service
```

Destructive full restore outline:

1. Stop the backup timer and media services.

```sh
systemctl stop appsdata-backup.timer
systemctl stop jellyfin audiobookshelf kavita postgresql podman-media-bookorbit radarr sonarr prowlarr bazarr podman-media-gluetun-webui podman-media-qbittorrent podman-media-sabnzbd podman-media-gluetun seerr flaresolverr
```

2. Mount the backup share.

```sh
mount /mnt/backups
```

3. Confirm snapshots exist.

```sh
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host media-vm --path /srv/appsdata --tag appsdata
```

4. Restore the selected tagged snapshot.

```sh
SNAPSHOT=<snapshot-id>
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic restore "$SNAPSHOT" \
    --host media-vm \
    --path /srv/appsdata \
    --tag appsdata \
    --target / \
    --verify
```

5. Reapply declared directories, normalize ownership for rebuilt users, keep
   `/srv/appsdata/prowlarr` owned by `nobody:nogroup` with mode `0700` for the
   Prowlarr DynamicUser bind mount, keep BookOrbit PostgreSQL paths owned by
   `postgres:postgres`, restart services, and validate.

```sh
systemd-tmpfiles --create
systemctl restart media-gluetun-control-auth-config.service
systemctl restart kavita-token-key.service
systemctl start postgresql jellyfin audiobookshelf kavita podman-media-bookorbit radarr sonarr prowlarr bazarr podman-media-gluetun podman-media-qbittorrent podman-media-sabnzbd podman-media-gluetun-webui seerr flaresolverr
systemctl start appsdata-backup.timer
systemctl start appsdata-restore-check.service
```

The same recovery outline is generated on `media-vm` at
`/etc/fleet/media-vm.md`. Keep this README and the generated recovery notes in
sync when backup or restore behavior changes.

## Operations

Check service status through Colmena:

```sh
colmena exec --on media-vm -- systemctl status jellyfin
colmena exec --on media-vm -- systemctl status postgresql
colmena exec --on media-vm -- systemctl status podman-media-bookorbit
colmena exec --on media-vm -- systemctl status podman-media-gluetun
colmena exec --on media-vm -- systemctl status podman-media-qbittorrent
colmena exec --on media-vm -- systemctl status podman-media-sabnzbd
colmena exec --on media-vm -- systemctl status podman-media-gluetun-webui
colmena exec --on media-vm -- systemctl status appsdata-backup.timer
```

Check SMB mounts on `media-vm`:

```sh
mount /mnt/media
ls -la /mnt/media
mount /mnt/backups
ls -la /mnt/backups
```

Roll back a NixOS generation from the host:

```sh
sudo nixos-rebuild switch --rollback
```

You can also reboot and choose an earlier generation from the bootloader.

## Safety Notes

- `hosts.nix` declares the `media-vm` disk as `/dev/sda`; any installer or partitioning command against that disk is destructive.
- Media files under `/mnt/media` are mounted from SMB and are not included in `appsdata-backup.service`.
- Restore appdata before first use of apps after rebuilding the VM, unless intentionally starting fresh.
- qBittorrent is intentionally tied to MediaVM Gluetun; do not add direct qBittorrent host networking or ports.
- Keep secret values encrypted before committing.
- Do not paste decrypted secrets into commits, issues, chat, logs, or shell history.
