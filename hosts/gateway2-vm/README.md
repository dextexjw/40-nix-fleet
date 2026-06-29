# gateway2-vm

`gateway2-vm` is the second Gateway node. It runs the same declarative Gateway
stack as `gateway-vm`: Authentik SSO, Traefik ingress, Homepage, Technitium DNS,
Gluetun, NetBird, and Tailscale.

The Proxmox VM shell is managed outside this repo in
`/home/smoke/code-cave/20-proxmox-infra-prov` as
`proxmox_virtual_environment_vm.gateway_vm[0]` under the `pve2/prod`
environment. Guest OS configuration, secrets, service deployment, and appdata
restore are managed here.

## Host Model

Important host values:

- FQDN: `gateway2.home.arpa`
- IP: `10.2.20.122`
- Gateway VIP: `10.2.20.102`
- Gateway: `10.2.20.1`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`
- VM RAM baseline: `3 GB`
- VM CPU cores: `2`

State paths:

- `/srv/appsdata/gluetun`
- `/srv/appsdata/authentik`
- `/srv/appsdata/technitium-dns-server`
- `/srv/appsdata/traefik`
- `/srv/appsdata/netbird`
- `/srv/appsdata/tailscale`

Gateway2 state is backed up with Restic to
`/mnt/backup/restic/appdata/gateway2-vm`. Initial state is seeded from the
latest `gateway-vm` appdata backup, then Gateway2 writes snapshots under its own
Restic host and repository identity.

## Bootstrap

Create or confirm the pve2 VM shell from the infra repo first:

```sh
cd /home/smoke/code-cave/20-proxmox-infra-prov
just pve2 prod check
just pve2 prod plan 'proxmox_virtual_environment_vm.gateway_vm[0]'
just pve2 prod output
```

After the NixOS base install is reachable at `10.2.20.122`, bootstrap from this
fleet repo:

```sh
nix develop
scripts/gateway2-vm/bootstrap-gateway2-vm.sh run
```

The bootstrap phases are resumable:

```sh
scripts/gateway2-vm/bootstrap-gateway2-vm.sh check-local-readiness
scripts/gateway2-vm/bootstrap-gateway2-vm.sh enable-vm-secret-access
scripts/gateway2-vm/bootstrap-gateway2-vm.sh dry-activate-gateway2-vm
scripts/gateway2-vm/bootstrap-gateway2-vm.sh deploy-gateway2-vm
scripts/gateway2-vm/bootstrap-gateway2-vm.sh verify-gateway2-vm
```

## State Seed

Seed Gateway2 from the latest primary Gateway backup:

```sh
nix develop
scripts/gateway2-vm/restore-from-gateway-vm-backup.sh
```

The restore script stops Gateway2 services, restores the latest
`gateway-vm` `/srv/appsdata` snapshot from
`/mnt/backup/restic/appdata/gateway-vm`, resets Tailscale and NetBird identity
state so Gateway2 can enroll independently, runs tmpfiles, restarts services,
runs Gateway2 backup/restore validation, and then runs the Gateway2 service
test.

## Upgrade And Validation

Use this flow for an already-running `gateway2-vm`:

```sh
nix develop
scripts/gateway2-vm/upgrade-gateway2-vm.sh run
```

Focused validation:

```sh
scripts/gateway2-vm/test-gateway2-services.sh
dig @10.2.20.122 gluetun.gateway.jax22.com
dig @10.2.20.102 gluetun.gateway.jax22.com
curl --resolve homepage.jax22.com:443:127.0.0.1 https://homepage.jax22.com/
```

## HA Scope

This host is the pve2 Gateway failover node. Keepalived uses unicast VRRP with
`gateway-vm` and elects one owner for the shared client VIP `10.2.20.102`.
`gateway-vm` has the higher priority and normally owns the VIP; `gateway2-vm`
takes it when the primary or its critical Gateway services fail.

Client DNS and service-zone forwarding should target `10.2.20.102`, not the
node-local address. Use `10.2.20.122` only for direct Gateway2 diagnostics,
bootstrap, and Colmena deployment.
