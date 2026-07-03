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
    resticPasswordFile
    serviceHosts
    serviceRouteLines
    statefulServices
    ;
in
{
  config = mkIf cfg.enable {
    environment.etc."fleet/productivity-vm.md".text = ''
        productivity-vm service model
        =============================

        productivity-vm runs Forgejo, Material for MkDocs, Paperless-ngx,
        FreshRSS, SearXNG, Vaultwarden, PrivateBin, Syncthing, Nextcloud,
        OpenSpeedTest, IT-Tools, Memos, netboot.xyz, iperf3, RustDesk, Shlink,
        Garage, RustFS, nginx, PostgreSQL, Redis, and Restic appdata backups.

        AFFiNE, Gitea, Stirling PDF, and Firefly III are testbed-vm-owned
        always-on services. Their public URLs are unchanged, but Gateway routes
        and Homepage monitors point at testbed-vm.

        Persistent state root:
          ${appdata}

        Backup repository:
          ${cfg.backup.repository}

        Password file:
          ${resticPasswordFile}

        Internal routes through Gateway nodes:
      ${serviceRouteLines}
        https://it-tools.jax22.com

        Direct LAN ports:
          Forgejo: ${toString cfg.ports.forgejo}
          SearXNG: ${toString cfg.ports.searxng}
          Vaultwarden: ${toString cfg.ports.vaultwarden}
          Syncthing GUI: ${toString cfg.ports.syncthing}
          OpenSpeedTest: ${toString cfg.ports.openspeedtest}
          IT-Tools: ${toString cfg.ports.itTools} (Gateway nodes only)
          netboot.xyz WebUI: ${toString cfg.netbootxyz.webUiPort}
          netboot.xyz assets: ${toString cfg.netbootxyz.assetPort}
          netboot.xyz TFTP UDP: ${toString cfg.netbootxyz.tftpPort}
          iperf3 TCP/UDP: ${toString cfg.ports.iperf3}
          Memos: ${toString cfg.ports.memos}
          RustDesk TCP: 21115, 21116, 21117, 21118, 21119
          RustDesk UDP: 21116
          Garage S3 API: ${toString cfg.ports.garageS3}
          Garage static web: ${toString cfg.ports.garageWeb}
          RustFS S3 API: ${toString cfg.ports.rustfsApi}
          RustFS console: ${toString cfg.ports.rustfsConsole}
          Shlink API and redirect service: ${toString cfg.ports.shlink}
          Shlink Web Client: ${toString cfg.ports.shlinkWeb}
          nginx-backed services: 80

        Backup validation:
          mount ${cfg.smb.backupMount}
          systemctl start productivity-appdata-backup.service
          systemctl start productivity-appdata-restore-check.service
          systemctl status productivity-appdata-backup.service productivity-appdata-restore-check.service

        Restore outline:
          1. Deploy productivity-vm once to create users, secrets, mounts, and units.
          2. Stop productivity-appdata-backup.timer and stateful services.
          3. Mount ${cfg.smb.backupMount}.
          4. Choose a productivity-vm/appsdata snapshot ID.
          5. Restore the snapshot to / with restic --verify.
          6. Run systemd-tmpfiles --create.
          7. Restart PostgreSQL and the stateful services.

        Services stopped during consistency-first manual backup:
          ${concatStringsSep " " statefulServices}

        Garage is standalone S3 in this pass. It does not back Nextcloud primary
        storage. ${serviceHosts.garage} is the authenticated S3 API, so anonymous
        browser requests to / should return AccessDenied. ${serviceHosts.garageWeb}
        is the static
        website endpoint; buckets must still be created and enabled for website
        hosting with the upstream Garage CLI before serving content. Garage
        bucket virtual-host style remains canonical on ${serviceHosts.garage} and
        ${serviceHosts.garageWeb}; the .h names are only routed named endpoints.
        garage-kaneo-bucket.service, garage-outline-bucket.service, and
        garage-plane-bucket.service import the SOPS-backed Garage keys, create
        buckets kaneo-uploads, outline-uploads, and plane-uploads, grant
        read/write access, and apply CORS for https://kaneo.jax22.com,
        https://outline.jax22.com, and https://plane.jax22.com.

        RustFS is a separate S3-compatible object store in this pass. It does not
        share Garage buckets or credentials. ${serviceHosts.rustfs} is the S3 API
        and ${serviceHosts.rustfsConsole} is the RustFS console. RustFS
        virtual-host style remains canonical on ${serviceHosts.rustfs}; the .h
        name is only a routed named endpoint. The console uses Authentik native
        OIDC for fleet-admins only. rustfs-oidc-policy.service keeps the
        rustfs-console-admin IAM policy present for OIDC console sessions; the
        S3 API remains access-key based through rustfs-environment. Authentik
        native OIDC provisioning attaches the self-signed signing key so RustFS
        can validate JWKS during startup discovery.

        RustDesk stores its server keypair under ${appdata}/rustdesk. Configure
        clients with ID server ${serviceHosts.rustdesk} and the public key from
        ${appdata}/rustdesk/id_ed25519.pub.

        iperf3 is available through gateway-vm and direct productivity-vm access:
        iperf3 -c ${serviceHosts.iperf3} -p ${toString cfg.ports.iperf3}

        IT-Tools runs as podman-it-tools.service on
        ${config.networking.hostName}:${toString cfg.ports.itTools}. It is
        stateless: saved tools/favorites live in browser local storage, so there
        is no /srv/appsdata/it-tools path, no SOPS secret, and no app-specific
        restore step. Gateway Traefik routes https://it-tools.jax22.com through
        Authentik forward-auth for productivity-users. No it-tools.h route is
        declared.

        Shlink uses the PostgreSQL database named shlink and the short-link route
        ${serviceHosts.shlink}. The local Shlink Web Client is served at
        ${serviceHosts.shlinkWeb}. Retrieve the API key from the encrypted
        shlink-environment secret and add http://${serviceHosts.shlink} as a server
        in the web client; do not publish the API key in web client static
        configuration.

        Memos stores its SQLite database and local app state under
        ${appdata}/memos. The pre-backup copy
        ${appdata}/memos-backups/latest.db is created with SQLite's backup
        command before Restic runs. memos-oidc-config.service provisions the
        Authentik OAuth2 provider with the encrypted memos-admin-pat and
        memos-oidc-client-secret secrets. Local password auth and signup policy
        remain managed in Memos.

        netboot.xyz stores persistent config and downloaded assets under
        ${cfg.netbootxyz.stateDir}. Gateway Traefik routes
        ${serviceHosts.netbootxyz} to ${config.networking.hostName} on
        ${toString cfg.netbootxyz.webUiPort}. Configure the LAN DHCP server
        option 66 to ${config.networking.hostName}.home.arpa or 10.2.20.114 and
        option 67 to netboot.xyz.efi. TFTP is direct UDP on
        ${toString cfg.netbootxyz.tftpPort}; Gateway does not proxy TFTP.

        Paperless OIDC uses the encrypted paperless-oidc-client-secret shared
        between gateway-vm Authentik provisioning and this host's paperless-owned
        generated runtime environment file. Authentik allows productivity-users,
        paperless-oidc-superuser promotes the SOPS-backed identity from
        paperless-admin-username or authentik-bootstrap-email to Paperless staff
        and superuser, and local Paperless password login remains enabled for
        break-glass access.

        Nextcloud OIDC uses the encrypted nextcloud-oidc-client-secret shared
        between gateway-vm Authentik provisioning and this host's
        nextcloud-oidc-config.service. The service configures the native
        user_oidc app for productivity-users while keeping local Nextcloud
        username/password login enabled for break-glass access. The local admin
        identity is sourced from nextcloud-admin-username and
        nextcloud-admin-password.

        RustFS OIDC uses the encrypted rustfs-oidc-client-secret shared between
        gateway-vm Authentik provisioning and this host's root-only generated
        RustFS environment file. Re-run rustfs-oidc-policy.service after RustFS
        appdata restores or RustFS root credential rotation.

    '';
  };
}
