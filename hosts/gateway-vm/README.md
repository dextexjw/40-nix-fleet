# gateway-vm

`gateway-vm` runs Authentik SSO, Traefik ingress, Homepage, Technitium DNS, Gluetun,
netboot.xyz, NetBird, and Tailscale.

Fleet inventory lives in `../../hosts.nix`. Host configuration lives in
`configuration.nix` and imports service modules from `../../modules/gateway/`.

## Host Model

Important host values:

- FQDN: `gateway-vm.home.arpa`
- IP: `10.2.20.112`
- Gateway: `10.2.20.1`
- DNS: `10.2.20.1`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`
- VM RAM: `8 GB`
- VM CPU cores: `4`

State paths:

- `/srv/appsdata/gluetun`
- `/srv/appsdata/netbootxyz`
- `/srv/appsdata/authentik`
- `/srv/appsdata/technitium-dns-server`
- `/srv/appsdata/traefik`
- `/srv/appsdata/netbird`
- `/srv/appsdata/tailscale`

Gateway state is backed up with Restic to
`/mnt/backup/restic/appdata/gateway-vm`. The restore-check target is
`/var/tmp/gateway-state-restore-check`.

## Service Access

Service access:

- Traefik HTTP ingress: `http://10.2.20.112`
- Traefik HTTPS ingress: `https://10.2.20.112` for `jax22.com` routes with Let’s Encrypt DNS-01 certificates
- Traefik dashboard: `http://10.2.20.112:8080/dashboard/`
- Traefik Prometheus metrics: `http://10.2.20.112:8080/metrics`
- Authentik: `https://auth.jax22.com/` through Traefik and `http://auth.h/` as an unprotected LAN alias; backend only on `127.0.0.1:9000`
- Homepage: `https://homepage.jax22.com/` through Traefik, `http://homepage.h/` as an alias, and `http://10.2.20.112:8082/` directly
- DNS: `10.2.20.112:53` over TCP and UDP
- DNS-over-TLS: `10.2.20.112:853`
- Technitium admin HTTP: `http://10.2.20.112:5380`
- Technitium HTTPS and DNS-over-HTTPS: `https://10.2.20.112:53443`
- Gluetun HTTP proxy: `http://10.2.20.112:8888`
- Gluetun WebUI: `https://gluetun.jax22.com/` through Traefik, `http://gluetun.h/` as an alias; backend only on `127.0.0.1:3000`
- MediaVM Gluetun WebUI: `https://media-gluetun.jax22.com/` through Traefik, `http://media-gluetun.h/` as an alias; backend on `10.2.20.113:3001`
- Checkmate: `https://checkmate.jax22.com/` through Traefik, `http://checkmate.h/` as an alias; backend on `10.2.20.115:52345`
- Beszel: `https://beszel.jax22.com/` through Traefik, `http://beszel.h/` as an alias; backend on `10.2.20.115:8090`
- netboot.xyz WebUI: `https://netbootxyz.jax22.com/` through Traefik, `http://netbootxyz.h/` as an alias; backend only on `127.0.0.1:3001`
- netboot.xyz local assets: backend only on `127.0.0.1:8083`
- netboot.xyz TFTP: `10.2.20.112:69/udp`, boot file `netboot.xyz.efi`
- NetBird: disabled for now; state preserved at `/srv/appsdata/netbird`
- Tailscale: `10.2.20.112:41641/udp`

Technitium admin HTTP is available directly at `http://10.2.20.112:5380` and
through Traefik at `https://technitium.jax22.com/` and `http://technitium.h/`.

Homepage is declared in Nix and generated into `/etc/homepage-dashboard`.
Gateway renders Homepage service groups and Traefik routes from the pure
owner-side exposure catalog in `hosts/*/exposure.nix` and
`modules/*/catalog.nix`. Gateway, Media, and Productivity sections use row
layouts with four cards per row. Homepage site monitors use direct backend URLs
for the internal HTTP cards so status checks do not depend on browser routing
through Traefik. A bottom `Links` bookmark section uses a compact three-column
layout with icons and service names for external references such as TorrentPeek,
GitHub, NixOS Search, Homepage docs, Traefik docs, and Technitium GitHub. It
does not use service API widgets or mutable UI configuration in this pass.

Authentik is the fleet identity provider. The canonical public URL is
`https://auth.jax22.com/`; `http://auth.h/` stays unprotected for LAN break-glass
access while `.h` is HTTP-only. Authentik runs as `authentik-server.service` and
`authentik-worker.service`, with PostgreSQL and Redis local to `gateway-vm`.
Persistent state lives under `/srv/appsdata/authentik`, including PostgreSQL,
Redis, uploaded media, and discovered certificates. The bootstrap admin password,
bootstrap API token, secret key, and PostgreSQL password are SOPS secrets.

Authentik is not attached as a Traefik forwardAuth proxy in front of fleet
applications. Browser routes are ordinary Traefik routes unless the application
has its own auth or a native SSO integration is configured. Role groups are
`fleet-admins`, `media-users`, `productivity-users`, and `monitoring-users`;
they are provisioned in Authentik for native app integrations.
Native OIDC integrations are provisioned from the route catalog. Beszel uses
the `beszel` client, allows `monitoring-users`, and uses
`https://beszel.jax22.com/api/oauth2-redirect` as the callback. Memos uses the
`memos` client, allows `productivity-users`, and uses
`https://memos.jax22.com/auth/callback` as the callback. Forgejo uses the
`forgejo` client, allows `productivity-users`, and uses
`https://forgejo.jax22.com/user/oauth2/authentik/callback` as the callback.
Paperless uses the `paperless` client, allows `productivity-users`, and uses
`https://paperless.jax22.com/accounts/oidc/authentik/login/callback/` as the
callback. RustFS Console uses
the `rustfs-console` client, allows `fleet-admins`, and uses
`https://rustfs-console.jax22.com/rustfs/admin/v3/oidc/callback/authentik` as
the callback. Native OIDC providers use Authentik's self-signed signing key so
the provider JWKS is populated for clients that validate discovery during
startup.

Future Authentik integrations should follow this pattern:

1. Prefer native OIDC. Do not put Authentik forwardAuth in front of ordinary
   browser routes unless the target app has no usable native SSO path and the
   proxy-only behavior is deliberately designed.
2. Declare the integration in the service exposure catalog, not manually in
   Authentik. For catalog helpers such as `mkService`, set `authMode`,
   `authGroups`, and `authOidc`; for hand-written entries, set the equivalent
   `auth` attribute:

   ```nix
   authMode = "native-oidc";
   authGroups = [ "productivity-users" ];
   authOidc = {
     clientId = "service-name";
     clientSecretFile = "/run/secrets/service-name-oidc-client-secret";
     launchUrl = "https://service-name.jax22.com/";
     redirectUris = [ "https://service-name.jax22.com/oidc/callback" ];
   };
   ```

3. Use exact callback URLs. `redirectUris` are provisioned as strict Authentik
   redirect URIs; include only callbacks the app actually uses.
4. Add one encrypted SOPS client-secret key per app. Gateway derives its
   Authentik-owned SOPS secret declarations from the catalog
   `clientSecretFile`; the app host must also expose the same secret to the app
   service user or app-specific OIDC config unit.
5. Configure the app side declaratively before service start. Use the same
   `clientId`, client secret, and Authentik discovery URL:
   `https://auth.jax22.com/application/o/<clientId>/.well-known/openid-configuration`.
   Keep local or break-glass login enabled until an interactive OIDC login is
   confirmed.
6. Let `authentik-provision.service` on `gateway-vm` create or update the
   Authentik provider, application, redirect URIs, OAuth scopes, signing key, and
   group bindings from `exposureCatalog.authentikApplications`. Native OIDC
   declarations without `clientSecretFile` or `redirectUris` fail Nix evaluation.
7. Update the app host README, readiness checks, and smoke tests. Gateway smoke
   checks are generated for Authentik discovery and authorize URLs from the
   catalog; the app host smoke test must still verify that the app sees the
   configured provider and that direct and routed health checks pass.
8. Deploy in order: create or confirm a fresh backup, dry/switch `gateway-vm`,
   dry/switch the app host, then run `scripts/gateway-vm/test-gateway-services.sh`
   and the app host smoke script.

Traefik writes JSON access logs to the `traefik.service` journal. Prometheus
metrics are exposed on the existing dashboard entrypoint at
`http://10.2.20.112:8080/metrics`. Public `jax22.com` service names also get
HTTPS routers on port 443 backed by a single Let’s Encrypt wildcard certificate
issued through Cloudflare DNS-01. The `.h` aliases remain HTTP-only. HTTP is not
redirected to HTTPS in this pass. ACME account and certificate state lives in
`/srv/appsdata/traefik/acme.json`, bind-mounted to `/var/lib/traefik/acme.json`,
and is included in Gateway appdata backups. OpenTelemetry tracing is declared in
the Gateway Traefik module but should only be enabled after an OTLP collector
endpoint is available.

`gateway-vm` intentionally pins Traefik to the upstream `3.7.1` Linux AMD64
release artifact, Technitium DNS to the upstream `15.2.0` source release, and
Gluetun to `ghcr.io/qdm12/gluetun@sha256:2f33c71e5e164fcd51a962cb950134df25155593edf0c3e1201f888d027049b4`
and netboot.xyz to `ghcr.io/netbootxyz/netbootxyz@sha256:942dfb60d11846b657a54dd36f1addf636b7736f38009223ce328ebc37f54d39`
while the rest of the fleet remains on the locked `nixpkgs` package set.

Gluetun uses Private Internet Access over OpenVPN. The HTTP proxy is exposed on
the LAN without separate proxy authentication; access is controlled by LAN
reachability and the host firewall. PIA VPN port forwarding and fixed region
selection are disabled for now. Gluetun's control API is authenticated with a
SOPS-managed API key and is only consumed by the WebUI sidecar inside Gluetun's
container network namespace.

The Gluetun WebUI runs as `podman-gluetun-webui.service` and is available on
the LAN through Traefik at `https://gluetun.jax22.com/` and `http://gluetun.h/`.
It has no native UI login, so
the direct backend listener stays bound to `127.0.0.1:3000` and is not opened
on the LAN as a separate port.

The MediaVM Gluetun WebUI runs on `media-vm` as
`podman-media-gluetun-webui.service`, shares the `media-gluetun` network
namespace used by qBittorrent and SABnzbd, and is available through Gateway Traefik at
`https://media-gluetun.jax22.com/` and `http://media-gluetun.h/`. Gateway only
routes to its MediaVM LAN backend on `10.2.20.113:3001`; the VPN container and
downloader kill switch still live on `media-vm`.

The netboot.xyz container runs as `podman-netbootxyz.service`. Its web
configuration UI is available through Traefik at `https://netbootxyz.jax22.com/`
and `http://netbootxyz.h/`, while the web UI backend on `127.0.0.1:3001` and local asset server on
`127.0.0.1:8083` stay host-local. TFTP is exposed on `10.2.20.112:69/udp` with
single-port transfers enabled. Persistent config and downloaded assets live
under `/srv/appsdata/netbootxyz`.

Technitium serves the `jax22.com` and `.h` service zones. Wildcard DNS resolves
`*.jax22.com` and `*.h` to `gateway-vm` at `10.2.20.112`, where Traefik routes
known hostnames to their backends. Traefik uses Cloudflare DNS-01 only for the
public `jax22.com` wildcard certificate; `.h` cannot be issued by Let’s Encrypt
and remains HTTP-only.
VM hostnames stay under `home.arpa` and are managed outside this Gateway
service zone. Clients must use `10.2.20.112` as DNS, or the LAN DNS/DHCP server
must forward/delegate `jax22.com` and `.h` to `10.2.20.112` on DNS port 53, for
these names to resolve. `jax22.com` is split-horizon for homelab clients, so
unrelated public records must be added or delegated deliberately if needed on
the LAN. Technitium's `5380` port is only the admin HTTP UI.

If a browser shows `DNS_PROBE_FINISHED_NXDOMAIN` for a service name, confirm
whether the client is asking Gateway DNS:

```sh
dig gluetun.jax22.com
dig @10.2.20.112 gluetun.jax22.com
dig gluetun.h
dig @10.2.20.112 gluetun.h
```

The first command must query `10.2.20.112`, or the LAN DNS server must have a
conditional forward/delegation for the service zone to `10.2.20.112` on DNS
port 53. A temporary single-client workaround is adding the specific service
hostname to that client's hosts file.

Traefik ingress routes are still declared explicitly, but the declarations now
live with their owning host or service catalog:

- Gateway-local routes: `hosts/gateway-vm/exposure.nix`
- Media routes/cards: `hosts/media-vm/exposure.nix` and `modules/media/catalog.nix`
- Productivity routes/cards: `hosts/productivity-vm/exposure.nix` and `modules/productivity/catalog.nix`
- Monitoring routes/cards: `hosts/monitoring-vm/exposure.nix` and `modules/monitoring/catalog.nix`

`gateway-vm` imports those pure data files and renders
`fleet.gateway.traefik.routes`, `fleet.gateway.homepage.serviceGroups`,
`/etc/fleet/gateway-vm.md`, and `/etc/fleet/gateway-exposure-smoke.tsv` from the
same source. Do not add broad wildcard Traefik routers or runtime service
registration.

Adding a Gateway-exposed service:

1. Add or update the owning service module.
2. Add the route/card/smoke metadata in the owning catalog or
   `hosts/<name>/exposure.nix`.
3. Run `nix flake check` and `colmena build --on gateway-vm`.
4. Use `scripts/gateway-vm/test-gateway-services.sh` after a future Gateway
   deploy to validate the generated DNS, Traefik route, and Homepage card checks.

Adding a Gateway-exposed VM:

1. Add the host inventory in `hosts.nix`.
2. Create `hosts/<name>/configuration.nix`; `flake.nix` includes only inventory
   hosts with a real configuration file in the Colmena hive.
3. Add `hosts/<name>/exposure.nix` and, for larger stacks, a module catalog
   under `modules/<domain>/catalog.nix`.

For netboot.xyz, configure the LAN DHCP server to point option 66 at
`10.2.20.112` and option 67 at `netboot.xyz.efi`. `gateway-vm` serves the
netboot.xyz web UI, local asset server, and TFTP, but does not take over DHCP
for the subnet.

## Secrets

Required secrets:

- `admin-password-hash`
- `authentik-bootstrap-email`
- `authentik-bootstrap-password`
- `authentik-bootstrap-token`
- `authentik-bootstrap-username`
- `authentik-postgresql-password`
- `authentik-secret-key`
- `beszel-oidc-client-secret`
- `forgejo-oidc-client-secret`
- `memos-oidc-client-secret`
- `nextcloud-oidc-client-secret`
- `paperless-oidc-client-secret`
- `rustfs-oidc-client-secret`
- `gluetun-control-api-key`
- `gluetun-openvpn-username`
- `gluetun-openvpn-password`
- `smb-credentials`
- `restic-password`
- `technitium-admin-username`
- `technitium-admin-password`
- `beszel-agent-key`
- `beszel-agent-token` (reserved for Beszel universal-token registration)
- `checkmate-capture-environment`
- `traefik-cloudflare-dns-api-token`

Normal edit flow:

```sh
nix develop
sops secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

`gateway-vm` decrypts secrets using `/etc/ssh/ssh_host_ed25519_key`. After a
new VM install or host key change, capture the host recipient:

```sh
ssh smoke@10.2.20.112 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

Add the printed `age1...` recipient to `.sops.yaml`, then rekey:

```sh
sops updatekeys secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

Keep `restic-password` stable. It is the encryption key for the Restic
repository; changing it makes existing snapshots unreadable with the new value.

## Bootstrap

Use this flow after preparing a fresh `gateway-vm` install. The destructive
`nixos-anywhere` VM install is managed outside this fleet repo before
declarative deployment begins.

```sh
nix develop
scripts/gateway-vm/bootstrap-gateway-vm.sh run
```

The bootstrap phases are resumable:

- `check-local-readiness`: verifies tools, encrypted secrets, `nix flake check`, and `colmena build --on gateway-vm`.
- `enable-vm-secret-access`: captures the gateway SSH host key, adds the age recipient to `.sops.yaml`, and runs `sops updatekeys`.
- `dry-activate-gateway-vm`: validates the activation plan with `colmena apply --on gateway-vm dry-activate`.
- `deploy-gateway-vm`: runs the guarded gateway deployment.
- `verify-gateway-vm`: confirms hostnames, service health, listener ports, Traefik routes, Gluetun proxy egress, and Restic backup/restore validation.

Individual phases:

```sh
scripts/gateway-vm/bootstrap-gateway-vm.sh check-local-readiness
scripts/gateway-vm/bootstrap-gateway-vm.sh enable-vm-secret-access
scripts/gateway-vm/bootstrap-gateway-vm.sh dry-activate-gateway-vm
scripts/gateway-vm/bootstrap-gateway-vm.sh deploy-gateway-vm
scripts/gateway-vm/bootstrap-gateway-vm.sh verify-gateway-vm
```

## Upgrade

Use this flow for an already-running `gateway-vm`. It deploys the current repo
state only; update and review `flake.lock` or host-local package pins
separately before running it.

```sh
nix develop
scripts/gateway-vm/upgrade-gateway-vm.sh run
```

The wrapper runs these phases in order:

- `check-upgrade-readiness`: verifies dev-shell tools, encrypted secrets, non-interactive SSH, `nix flake check`, and `colmena build --on gateway-vm`.
- `create-pre-upgrade-backup`: starts a gateway appdata Restic backup and lists the latest matching snapshots.
- `dry-activate-gateway-vm`: validates the activation plan with `colmena apply --on gateway-vm dry-activate`.
- `deploy-gateway-vm`: runs the guarded `gateway-vm` deployment and normalizes the transient hostname.
- `verify-gateway-vm`: confirms service health, listener ports, Traefik routes, DNS records, Gluetun proxy egress, backup/restore validation, and tmpfiles declarations.

The upgrade workflow never restores appdata automatically. Use the restore
workflow only when recovering from a failed host or bad application state.

The phases can also be run individually:

```sh
scripts/gateway-vm/upgrade-gateway-vm.sh check-upgrade-readiness
scripts/gateway-vm/upgrade-gateway-vm.sh create-pre-upgrade-backup
scripts/gateway-vm/upgrade-gateway-vm.sh dry-activate-gateway-vm
scripts/gateway-vm/upgrade-gateway-vm.sh deploy-gateway-vm
scripts/gateway-vm/upgrade-gateway-vm.sh verify-gateway-vm
```

## Deploy

Use plain Colmena commands from inside `nix develop`.

```sh
colmena build --on gateway-vm
colmena apply --on gateway-vm dry-activate
colmena apply --on gateway-vm switch
```

The guarded deploy helper checks local SOPS decryption and confirms the VM has
a matching SOPS recipient before switching:

```sh
scripts/gateway-vm/deploy-gateway.sh
```

## Backups and Restore

`gateway-vm` backs up `/srv/appsdata` with Restic.

- Service: `gateway-state-backup.service`
- Timer: `gateway-state-backup.timer`
- Source: `/srv/appsdata`
- Repository: `/mnt/backup/restic/appdata/gateway-vm`
- Password file: `/run/secrets/restic-password`
- Non-destructive restore validation: `gateway-state-restore-check.service`

Recommended consistency-first manual backup from the repo development shell:

```sh
scripts/gateway-vm/create-gateway-backup.sh
```

That script mounts `/mnt/backup`, stops the Gateway backup timer, stops active
stateful Gateway services, runs the Restic backup and restore validation, lists
recent snapshots, restarts services and the timer, then runs the normal Gateway
service validation.

Post-deploy validation:

```sh
scripts/gateway-vm/test-gateway-services.sh
```

That script verifies service health, listener ports, Traefik HTTP and HTTPS routes, DNS
records, Gluetun proxy egress, netboot.xyz TFTP fetches, Homepage generated
config, and gateway state backup/restore validation.

Lower-level backup and restore validation on `gateway-vm` for debugging:

```sh
mount /mnt/backup
systemctl start gateway-state-backup.service
systemctl start gateway-state-restore-check.service
systemctl status gateway-state-backup.service gateway-state-restore-check.service
```

Restore outline:

1. Deploy `gateway-vm` once to create users, secrets, mounts, and units.
2. Stop Traefik, Technitium, Gluetun, netboot.xyz, NetBird, and Tailscale before replacing state.
3. Mount `/mnt/backup`.
4. Choose a `gateway-vm` appdata snapshot ID.
5. Restore the snapshot to `/` with `restic --verify`.
6. Run `systemd-tmpfiles --create`.
7. Restart `traefik.service`, `homepage-dashboard.service`, `technitium-dns-server.service`, `podman-gluetun.service`, `podman-gluetun-webui.service`, `podman-netbootxyz.service`, and `tailscaled.service`; restart `netbird.service` too if NetBird is re-enabled.

Homepage has no authoritative mutable app state in this fleet pass. Restore its
dashboard by redeploying the Gateway Nix configuration.

The same service and recovery model is generated on `gateway-vm` at
`/etc/fleet/gateway-vm.md`. Keep this README and the generated recovery notes
in sync when backup or restore behavior changes.

## Operations

Check service status through Colmena:

```sh
colmena exec --on gateway-vm -- systemctl status traefik
colmena exec --on gateway-vm -- systemctl status homepage-dashboard
colmena exec --on gateway-vm -- systemctl status technitium-dns-server
colmena exec --on gateway-vm -- systemctl status podman-gluetun
colmena exec --on gateway-vm -- systemctl status podman-gluetun-webui
colmena exec --on gateway-vm -- systemctl status podman-netbootxyz
colmena exec --on gateway-vm -- systemctl status tailscaled
colmena exec --on gateway-vm -- systemctl status gateway-state-backup.timer
```

Roll back a NixOS generation from the host:

```sh
sudo nixos-rebuild switch --rollback
```

You can also reboot and choose an earlier generation from the bootloader.

## Safety Notes

- `hosts.nix` declares the `gateway-vm` disk as `/dev/sda`; any installer or partitioning command against that disk is destructive.
- `gateway-vm` serves netboot.xyz TFTP and the web UI but does not take over DHCP for the subnet.
- Keep auth keys, DNS API tokens, and service secrets in encrypted secrets only.
- Do not write plaintext secrets into Nix files, generated configs, recovery notes, logs, or chat.
