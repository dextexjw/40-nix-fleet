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

        productivity-vm runs AFFiNE, the On-Demand Apps Dashboard, Gitea, Forgejo,
        Material for MkDocs, Paperless-ngx, FreshRSS, SearXNG, Vaultwarden,
        PrivateBin, Syncthing, Stirling PDF, Firefly III, Nextcloud,
        OpenSpeedTest, InvoicePlane, Memos, netboot.xyz, iperf3, RustDesk,
        Shlink, Garage, RustFS, nginx, PostgreSQL, MariaDB, Redis, and
        Restic appdata backups.

        Persistent state root:
          ${appdata}

        Backup repository:
          ${cfg.backup.repository}

        Password file:
          ${resticPasswordFile}

        Internal routes through Gateway nodes:
      ${serviceRouteLines}

        Direct LAN ports:
          AFFiNE: ${toString cfg.ports.affine}
          On-Demand Apps Dashboard: ${toString cfg.onDemandLauncher.port} (Gateway nodes only)
          Gitea: ${toString cfg.ports.gitea}
          Forgejo: ${toString cfg.ports.forgejo}
          SearXNG: ${toString cfg.ports.searxng}
          Vaultwarden: ${toString cfg.ports.vaultwarden}
          Syncthing GUI: ${toString cfg.ports.syncthing}
          Stirling PDF: ${toString cfg.ports.stirlingPdf}
          OpenSpeedTest: ${toString cfg.ports.openspeedtest}
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
          systemctl start productivity-consistency-backup.service
          systemctl start productivity-appdata-restore-check.service
          systemctl status productivity-consistency-backup.service productivity-appdata-backup.service productivity-appdata-restore-check.service

        Restore outline:
          1. Deploy productivity-vm once to create users, secrets, mounts, and units.
          2. Stop productivity-appdata-backup.timer and stateful services.
          3. Mount ${cfg.smb.backupMount}.
          4. Choose a productivity-vm/appsdata snapshot ID.
          5. Restore the snapshot to / with restic --verify.
          6. Run systemd-tmpfiles --create.
          7. Restart PostgreSQL, MariaDB, and the stateful services.

        Services stopped during consistency-first manual backup:
          ${concatStringsSep " " statefulServices}

        On-demand productivity apps:
          Launcher: ${cfg.onDemandLauncher.publicBaseUrl}
          Backend: ${config.networking.hostName}:${toString cfg.onDemandLauncher.port}, source-restricted to Gateway nodes
          Bundles:
            affine: redis-affine.service, podman-affine.service
            gitea: gitea.service, gitea-oidc-config.service
            stirling-pdf: stirling-pdf.service
            firefly: phpfpm-firefly-iii.service, firefly-iii-cron.timer
          AFFiNE, Gitea, Stirling PDF, and Firefly III are installed but not
          wanted by boot targets. Homepage links those cards to the launcher.
          The launcher refuses actions while backup, restore-check, dump,
          migration, or deployment lock signals are active. The scheduled
          consistency backup and manual backup helper preserve each on-demand
          app's pre-backup running/stopped state; destructive restore leaves
          on-demand apps stopped until relaunched.

        Garage is standalone S3 in this pass. It does not back Nextcloud primary
        storage. ${serviceHosts.garage} is the authenticated S3 API, so anonymous
        browser requests to / should return AccessDenied. ${serviceHosts.garageWeb}
        is the static
        website endpoint; buckets must still be created and enabled for website
        hosting with the upstream Garage CLI before serving content. Garage
        bucket virtual-host style remains canonical on ${serviceHosts.garage} and
        ${serviceHosts.garageWeb}; the .h names are only routed named endpoints.
        garage-kaneo-bucket.service imports the SOPS-backed Kaneo Garage key,
        creates bucket kaneo-uploads, grants read/write access, and applies CORS
        for https://kaneo.jax22.com.

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

        InvoicePlane uses MariaDB database invoiceplane and persistent runtime state
        under ${appdata}/invoiceplane. Initial setup is completed through
        http://${serviceHosts.invoiceplane}/index.php/setup, then setup should be
        locked in ${appdata}/invoiceplane/www/ipconfig.php with DISABLE_SETUP=true.

        RustDesk stores its server keypair under ${appdata}/rustdesk. Configure
        clients with ID server ${serviceHosts.rustdesk} and the public key from
        ${appdata}/rustdesk/id_ed25519.pub.

        iperf3 is available through gateway-vm and direct productivity-vm access:
        iperf3 -c ${serviceHosts.iperf3} -p ${toString cfg.ports.iperf3}

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

        Gitea OIDC uses the encrypted gitea-oidc-client-secret shared between
        gateway-vm Authentik provisioning and gitea-oidc-config.service.
        Authentik allows productivity-users, and local Gitea username/password
        login remains enabled for break-glass access. Gitea is started on demand
        through the On-Demand Apps Dashboard.

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

        AFFiNE stores uploaded blobs and custom config under ${appdata}/affine
        and uses the PostgreSQL database named affine. The AFFiNE container runs
        database migrations before each server start through podman-affine.service
        and uses a host-local redis-affine.service instance as volatile cache and
        job state. AFFiNE is started on demand through the On-Demand Apps
        Dashboard. affine-environment supplies DB_PASSWORD; the derived
        DATABASE_URL is generated at runtime under /run/affine/environment so it
        is not stored in the Nix store. Authentik provisions the affine OIDC
        client for productivity-users with callback
        https://affine.jax22.com/oauth/callback. Finish the app-side OIDC setup
        in AFFiNE Admin Panel > Settings > OAuth with issuer
        https://auth.jax22.com/application/o/affine, client ID affine, and the
        encrypted affine-oidc-client-secret.
    '';
  };
}
