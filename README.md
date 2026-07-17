# Homelab NixOS Fleet

This repository is my personal NixOS homelab fleet. It is managed as a Nix
flake and deployed with Colmena.

The current fleet is intentionally small:

- `gateway-vm` runs Traefik ingress, Technitium DNS, NetBird, and Tailscale as
  the preferred owner of the `10.2.20.102` Gateway VIP.
- `gateway2-vm` runs the same Gateway stack as the pve2 failover node for the
  `10.2.20.102` Gateway VIP.
- `media-vm` runs Jellyfin, Audiobookshelf, Kavita, declaratively provisioned BookOrbit, ARR apps, Gluetun-gated downloads, SMB media mounts, and appdata backups.
- `productivity-vm` runs Forgejo, docs, documents, RSS, search, vault, file sync, cloud files, speed tests, IT-Tools, remote desktop relay, notes, short links, S3-compatible object storage, netboot.xyz, and appdata backups.
- `monitoring-vm` runs Checkmate, Beszel, ntfy notifications, fleet monitoring agents, and appdata backups.
- `testbed-vm` runs AFFiNE, Gitea, Stirling PDF, Firefly III, Homebox, InvoicePlane, Kaneo, Listmonk, Plane, Sure, and Mailpit SMTP capture with appdata backups.

Treat this repo as the source of truth for hosts, services, secrets workflow,
and recovery notes. The fleet-wide service standard is captured in
`PRINCIPLES.md`; new Gateway, Security, Identity, and other service modules
should follow that blueprint before being treated as production-ready.

## Current Hosts

| Host | IP | Tags | Role | Runbook |
| --- | --- | --- | --- | --- |
| `gateway-vm` | `10.2.20.112` | `control-plane`, `gateway`, `exposure-consumer` | Preferred Gateway VIP owner, ingress, DNS, mesh networking | [`hosts/gateway-vm/README.md`](hosts/gateway-vm/README.md) |
| `gateway2-vm` | `10.2.20.122` | `gateway`, `exposure-consumer` | Gateway VIP failover node on pve2 | [`hosts/gateway2-vm/README.md`](hosts/gateway2-vm/README.md) |
| `media-vm` | `10.2.20.113` | `media` | Media services, BookOrbit, Gluetun-gated downloads, SMB media, Restic appdata backups | [`hosts/media-vm/README.md`](hosts/media-vm/README.md) |
| `productivity-vm` | `10.2.20.114` | `productivity`, `exposure-consumer` | Productivity services, documents, Forgejo, speed tests, IT-Tools, remote desktop relay, notes, short links, object storage, netboot, Restic appdata backups | [`hosts/productivity-vm/README.md`](hosts/productivity-vm/README.md) |
| `monitoring-vm` | `10.2.20.115` | `monitoring`, `exposure-consumer` | Checkmate, Beszel, ntfy notifications, fleet monitoring agents, Restic appdata backups | [`hosts/monitoring-vm/README.md`](hosts/monitoring-vm/README.md) |
| `testbed-vm` | `10.2.20.129` | `testbed`, `exposure-consumer` | AFFiNE, Gitea, Stirling PDF, Firefly III, Homebox inventory testbed, InvoicePlane invoicing testbed, Kaneo and Plane project-management testbeds, Listmonk newsletter testbed, Sure personal-finance testbed, Mailpit local and homelab SMTP capture, Restic appdata backups | [`hosts/testbed-vm/README.md`](hosts/testbed-vm/README.md) |

Inventory lives in `hosts.nix`. Per-host configuration and host-specific
runbooks live under `hosts/<name>/`.

## Repository Map

- `flake.nix`: inputs, development shell, and Colmena hive.
- `hosts.nix`: host IPs, users, tags, nameservers, and VM constants.
- `lib/gateway-cluster.nix`: Gateway cluster members, primary node, member IPs,
  and the shared `10.2.20.102` client VIP.
- `hosts/common.nix`: shared Nix, SSH, user, firewall, package, and node-exporter defaults.
- `hosts/gateway-vm/`: primary gateway configuration, hardware profile, exposure catalog, and runbook.
- `hosts/gateway2-vm/`: second gateway hardware profile and runbook; service configuration is shared with `gateway-vm`.
- `hosts/media-vm/`: media host configuration, hardware profile, and runbook.
- `hosts/productivity-vm/`: productivity host configuration, hardware profile, and runbook.
- `hosts/monitoring-vm/`: monitoring host configuration, hardware profile, exposure catalog, and runbook.
- `hosts/testbed-vm/`: testbed host configuration, hardware profile, exposure catalog, and runbook.
- `modules/gateway/`: Traefik, Technitium, NetBird, Tailscale, and gateway backup modules.
- `modules/media/`: the `media-vm` service modules, SMB mounts, backups, and recovery notes.
- `modules/productivity/`: the `productivity-vm` service modules, netboot.xyz, PostgreSQL, backups, and recovery notes.
- `modules/monitoring/`: Checkmate, Beszel, ntfy, fleet monitoring agents, and available Prometheus/Grafana/node exporter modules.
- `modules/testbed/`: the `testbed-vm` Homebox, InvoicePlane, Kaneo, Listmonk, Plane, Sure, Mailpit, MariaDB, PostgreSQL, backups, and recovery notes.
- `modules/networking/reverse-proxy.nix`: available nginx virtual hosts module.
- `modules/security/self-signed-ca.nix`: internal self-signed CA and per-domain cert generation.
- `modules/dev/`: available Jenkins and Gitea modules.
- `modules/apps/freshrss.nix`: available module, not currently enabled.
- `secrets/example-secrets.yaml`: expected SOPS secret shape.
- `secrets/secrets.yaml`: encrypted real secrets.
- `scripts/<host>/`: local helper scripts grouped by host.
- `scripts/dev-ubuntu/`: operator workstation bootstrap and migration helpers for `smoke@dev.ubuntu.home.arpa`.

## Documentation Model

Use the root README as the fleet map: what exists, how the repo is organized,
and how to deploy safely.

Use the host READMEs as operational runbooks:

- [`hosts/gateway-vm/README.md`](hosts/gateway-vm/README.md): direct ports, Traefik routes, state backup, bootstrap, and validation.
- [`hosts/gateway2-vm/README.md`](hosts/gateway2-vm/README.md): pve2 infra handoff, Gateway2 bootstrap, state seed, backup, and validation.
- [`hosts/media-vm/README.md`](hosts/media-vm/README.md): service URLs, media/appdata paths, SMB mounts, secrets, bootstrap, upgrade, backup, restore, and validation.
- [`hosts/productivity-vm/README.md`](hosts/productivity-vm/README.md): service URLs, appdata paths, secrets, bootstrap, upgrade, backup, restore, and validation.
- [`hosts/monitoring-vm/README.md`](hosts/monitoring-vm/README.md): service URLs, appdata paths, secrets, bootstrap, upgrade, backup, restore, and validation.
- [`hosts/testbed-vm/README.md`](hosts/testbed-vm/README.md): Homebox, InvoicePlane, Kaneo, Listmonk, Sure URLs, Mailpit capture, appdata paths, secrets, bootstrap, upgrade, backup, restore, and validation.

Generated on-host notes under `/etc/fleet/<host>.md` are emergency recovery
references. Keep them aligned with the host README when changing backup,
restore, or service recovery behavior.

## Local Workflow

Enter the development shell before using Colmena, SOPS, age, Restic, or the
helper scripts:

```sh
nix develop
```

With `direnv`, `.envrc` loads the same flake shell automatically.

Useful local checks:

```sh
scripts/check.sh
nix flake check
colmena build --on media-vm
colmena apply --on media-vm dry-activate
colmena build --on gateway2-vm
colmena apply --on gateway2-vm dry-activate
colmena build --on productivity-vm
colmena apply --on productivity-vm dry-activate
colmena build --on monitoring-vm
colmena apply --on monitoring-vm dry-activate
colmena build --on testbed-vm
colmena apply --on testbed-vm dry-activate
```

`media-vm` also has a focused check helper:

```sh
scripts/media-vm/check.sh
```

`scripts/check.sh` is the repo-wide hygiene gate. It checks shell syntax,
required-secret manifests, Nix formatting, and `nix flake check`; ShellCheck,
Statix, and Deadnix run as advisory checks from the dev shell.

### Stateless service lifecycle command

Use `scripts/fleet-lifecycle.py` as the canonical planning and validation
interface for a stateless service addition or edit. It evaluates `hosts.nix`,
reports the runtime owner and every generated exposure consumer, then
delegates to `scripts/check.sh` and the standard Colmena build and dry-activate
commands for every affected host.

```sh
scripts/fleet-lifecycle.py plan \
  --action addition \
  --host productivity-vm \
  --service-class stateless

scripts/fleet-lifecycle.py validate \
  --action edit \
  --host testbed-vm \
  --service-class stateless \
  --evidence /tmp/testbed-lifecycle.json
```

For additions, consumer impact defaults to `generated`. For edits, `auto`
inspects working-tree paths and includes every host tagged
`exposure-consumer` when the owning catalog, exposure definition, or shared
exposure libraries changed; otherwise the scope remains host-local. Use
`--consumer-impact generated` or `--consumer-impact host-local` only to record
an explicit applicability override when path discovery cannot express the
change.

Both operations are non-mutating and never run a Colmena switch. A live switch
requires separate explicit authorization and the owning host's guarded deploy
workflow. `plan` intentionally leaves required execution gates `not_run`, so it
returns a non-zero incomplete outcome; `validate` returns success only when all
required static, build, and dry-activation gates pass.

Command progress and delegated output go to standard error, while standard
output contains only the structured JSON report. It uses stable gate statuses: `passed`, `failed`,
`blocked`, `not_run`, and `not_applicable`. Every `not_applicable` result has a
reason. A required `failed`, `blocked`, or `not_run` gate makes the overall
outcome `incomplete` and the command exits non-zero. The report is printed to
standard output and is also written to the path supplied with `--evidence`.

## Ubuntu Development Base

`smoke@dev.ubuntu.home.arpa` is the preferred operator workstation for this
fleet. It hosts the Nix repos and runs `nix develop`, Colmena builds,
dry-activations, Codex, and the Hermes gateway. It is intentionally not a
Colmena/NixOS fleet node.

Before bootstrapping, resize the VM disk to at least 80 GiB. The helper refuses
to install Nix or agent state on the original tiny cloud image disk.

Bootstrap the Ubuntu host after the hypervisor disk resize:

```sh
scripts/dev-ubuntu/bootstrap-dev-base.sh
```

The bootstrap helper verifies Ubuntu 26.04, grows `/dev/sda1`, installs base
packages and the multi-user Nix daemon, enables flakes, installs Codex and
Hermes, creates their user update timers, and enables linger for `smoke`.

Migrate the current NixOS dev host after bootstrap succeeds:

```sh
scripts/dev-ubuntu/migrate-from-dev-nix.sh
```

The migration helper copies `/home/smoke/code-cave` from
`smoke@dev.nix.home.arpa`, preserving dirty worktrees. It also copies the SSH
client identity, Codex runtime state, and Hermes runtime state over SSH only,
regenerates the Hermes gateway unit on Ubuntu, starts it there, then disables
the old Hermes gateway and update timer on `dev.nix.home.arpa`.

Post-cutover checks from `dev-ubuntu`:

```sh
df -h /
nix --version
codex --version
hermes --version
systemctl --user is-active hermes-gateway.service
systemctl --user list-timers codex-auto-update.timer hermes-nix-update.timer
cd ~/code-cave/40-nix-fleet
nix develop
scripts/check.sh
nix flake check
colmena build --on media-vm
colmena apply --on media-vm dry-activate
```

## Deployments

Use plain Colmena commands from inside `nix develop`.

Deploy one host:

```sh
colmena apply --on media-vm switch
colmena apply --on gateway-vm switch
colmena apply --on gateway2-vm switch
colmena apply --on productivity-vm switch
colmena apply --on monitoring-vm switch
colmena apply --on testbed-vm switch
```

Deploy by tag only when intentionally targeting a group:

```sh
colmena apply --on @media switch
colmena apply --on @gateway switch
colmena apply --on @productivity switch
colmena apply --on @monitoring switch
colmena apply --on @testbed switch
```

Deploy the whole fleet only when that is really the goal:

```sh
colmena apply switch
```

Guarded deploy helpers check local SOPS decryption and confirm the target VM has
a matching SOPS recipient before switching:

```sh
scripts/media-vm/deploy-media.sh
scripts/gateway-vm/deploy-gateway.sh
scripts/gateway2-vm/deploy-gateway2.sh
scripts/productivity-vm/deploy-productivity.sh
scripts/monitoring-vm/deploy-monitoring.sh
scripts/testbed-vm/deploy-testbed.sh
```

See the host runbooks for bootstrap, upgrade, backup, restore, and validation
flows.

## Secrets

Secrets are managed with SOPS and deployed through `sops-nix`.

Expected shared secrets:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`

Service-specific secrets are documented in the host runbooks and
`secrets/example-secrets.yaml`.

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

Each VM decrypts secrets using `/etc/ssh/ssh_host_ed25519_key`. After a new VM
install or host key change, capture the host recipient, add the printed
`age1...` value to `.sops.yaml`, then rekey:

```sh
ssh smoke@10.2.20.113 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
ssh smoke@10.2.20.112 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
ssh smoke@10.2.20.122 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
ssh smoke@10.2.20.114 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
ssh smoke@10.2.20.115 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
ssh smoke@10.2.20.129 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
sops updatekeys secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

Keep `restic-password` stable. It is the encryption key for Restic
repositories; changing it makes existing snapshots unreadable with the new
value.

## Changing the Fleet

Service modules live under `modules/<domain>/` and expose options under the
`fleet.<domain>.<service>` namespace. Follow the existing module shape:

1. Define options under `options`.
2. Gate implementation with `mkIf cfg.enable`.
3. Import the module from the host that should run it.
4. Enable it in that host's `fleet.*` config.
5. Run `nix flake check`, build the host, and dry-activate before switching.

For `media-vm` changes touching the media stack, SMB mounts, SOPS secrets, or
Restic, deploy and then run:

```sh
scripts/media-vm/test-media-backup.sh
```

Keep README changes and `/etc/fleet/<host>.md` recovery notes aligned when
backup, restore, or recovery behavior changes.

## Safety Notes

- Host disks are declared in `hosts.nix`; installer or partitioning commands against those disks are destructive.
- App stack backups use `/mnt/backups`; Gateway state backup intentionally uses
  `/mnt/backup` until that live path is migrated.
- Keep secret values encrypted before committing.
- Do not paste decrypted secrets into commits, issues, chat, logs, or shell history.
- The base firewall opens SSH and service modules open their own required ports.
- `gateway-vm` serves declarative `jax22.com` and `.h` service zones in
  Technitium; clients should use the Gateway VIP `10.2.20.102` for DNS, or the
  LAN DNS/DHCP server must forward or delegate those zones to `10.2.20.102` on DNS port 53,
  before browser URLs like `traefik.jax22.com` or `traefik.h` will resolve.
  `gateway-vm` and `gateway2-vm` both serve the same service catalog and
  keepalived elects one owner for `10.2.20.102`.
  `jax22.com` is split-horizon for homelab clients, so unrelated public records
  must be handled separately if they are needed on the LAN. Technitium's `5380`
  port is only the admin HTTP UI. VM hostnames stay under `home.arpa` and are
  managed separately.
