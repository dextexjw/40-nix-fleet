{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.technitium;
  localZones =
    cfg.localZones
    ++ optional cfg.localZone.enable {
      inherit (cfg.localZone) aRecords domain;
    };
  mkLocalZoneRecordCommands =
    zone:
    let
      records = mapAttrsToList (name: address: {
        address = address;
        domain = if name == "@" then zone.domain else "${name}.${zone.domain}";
      }) zone.aRecords;
    in
    concatMapStringsSep "\n" (record: ''
      api_expect_ok "add ${record.domain} A record" "$base/api/zones/records/add" \
        --data-urlencode "domain=${record.domain}" \
        --data-urlencode "zone=${zone.domain}" \
        --data-urlencode "type=A" \
        --data-urlencode "ipAddress=${record.address}" \
        --data-urlencode "overwrite=true"
    '') records;
  localZoneCommands = concatMapStringsSep "\n" (zone: ''
    api_expect_ok_or_exists "create ${zone.domain} zone" "$base/api/zones/create" \
      --data-urlencode "zone=${zone.domain}" \
      --data-urlencode "type=Primary"

    ${mkLocalZoneRecordCommands zone}
  '') localZones;
  adminPasswordFileArg =
    if cfg.adminPasswordFile == null then "''" else escapeShellArg cfg.adminPasswordFile;
  adminUsernameFileArg =
    if cfg.adminUsernameFile == null then "''" else escapeShellArg cfg.adminUsernameFile;
  bool = value: if value then "true" else "false";
  certificatePath = "/var/lib/technitium-dns-server/tls/${cfg.tlsCertificateDomain}.pfx";
  sanList = concatStringsSep "," cfg.tlsSubjectAltNames;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.technitium = {
    enable = mkEnableOption "Technitium DNS Server";

    adminPasswordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime secret file containing the Technitium admin password.";
    };

    adminUsernameFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime secret file containing the Technitium admin username.";
    };

    configureEncryptedDns = mkOption {
      type = types.bool;
      default = true;
      description = "Configure DNS-over-TLS and DNS-over-HTTPS through the Technitium API.";
    };

    dnsOverTlsPort = mkOption {
      type = types.port;
      default = 853;
      description = "DNS-over-TLS port to allow through the firewall.";
    };

    dnsPort = mkOption {
      type = types.port;
      default = 53;
      description = "Recursive DNS port.";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 53443;
      description = "Technitium HTTPS and DNS-over-HTTPS port.";
    };

    localZone = {
      aRecords = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "A records to publish in the local gateway DNS zone.";
        example = {
          technitium = "10.2.20.112";
          gateway-vm = "10.2.20.112";
        };
      };

      domain = mkOption {
        type = types.str;
        default = "home.arpa";
        description = "Authoritative local DNS zone served by Technitium.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Create and maintain a local authoritative DNS zone.";
      };
    };

    localZones = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            aRecords = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "A records to publish in this local gateway DNS zone.";
              example = {
                "*" = "10.2.20.112";
              };
            };

            domain = mkOption {
              type = types.str;
              description = "Authoritative local DNS zone served by Technitium.";
              example = "jax22.com";
            };
          };
        }
      );
      default = [ ];
      description = "Additional authoritative local DNS zones served by Technitium.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.technitium-dns-server;
      defaultText = literalExpression "pkgs.technitium-dns-server";
      description = "Technitium DNS Server package to run.";
    };

    serverDomain = mkOption {
      type = types.str;
      default = config.networking.fqdnOrHostName;
      description = "Primary domain name Technitium uses to identify this DNS server.";
    };

    tlsCertificateDomain = mkOption {
      type = types.str;
      default = config.networking.fqdnOrHostName;
      description = "Domain name used for the generated local TLS certificate.";
    };

    tlsSubjectAltNames = mkOption {
      type = types.listOf types.str;
      default = [ "DNS:${cfg.tlsCertificateDomain}" ];
      description = "Subject alternative names for the generated local TLS certificate.";
    };

    webPort = mkOption {
      type = types.port;
      default = 5380;
      description = "Technitium HTTP administration port.";
    };

    webServiceLocalAddresses = mkOption {
      type = types.str;
      default = "127.0.0.1,::1";
      description = "Comma-separated local addresses for the Technitium web console.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    services.technitium-dns-server = {
      enable = true;
      openFirewall = true;
      package = cfg.package;
      firewallTCPPorts = unique [
        cfg.dnsPort
        cfg.dnsOverTlsPort
        cfg.httpsPort
        cfg.webPort
      ];
      firewallUDPPorts = [ cfg.dnsPort ];
    };

    systemd.services.technitium-dns-server = {
      environment = {
        DNS_SERVER_DOMAIN = cfg.serverDomain;
        DNS_SERVER_RECURSION = "AllowOnlyForPrivateNetworks";
        DNS_SERVER_WEB_SERVICE_HTTP_PORT = toString cfg.webPort;
        DNS_SERVER_WEB_SERVICE_LOCAL_ADDRESSES = cfg.webServiceLocalAddresses;
      }
      // optionalAttrs (cfg.adminPasswordFile != null) {
        DNS_SERVER_ADMIN_PASSWORD_FILE = "%d/technitium-admin-password";
      };

      preStart = mkIf cfg.configureEncryptedDns ''
        set -euo pipefail

        state_dir="''${STATE_DIRECTORY:-/var/lib/technitium-dns-server}"
        cert_dir="$state_dir/tls"
        mkdir -p "$cert_dir"

        if [ ! -s "$cert_dir/${cfg.tlsCertificateDomain}.pfx" ]; then
          ${pkgs.openssl}/bin/openssl req \
            -x509 \
            -newkey rsa:4096 \
            -sha256 \
            -days 3650 \
            -nodes \
            -subj ${escapeShellArg "/CN=${cfg.tlsCertificateDomain}"} \
            -addext ${escapeShellArg "subjectAltName=${sanList}"} \
            -keyout "$cert_dir/${cfg.tlsCertificateDomain}.key.pem" \
            -out "$cert_dir/${cfg.tlsCertificateDomain}.crt.pem"

          ${pkgs.openssl}/bin/openssl pkcs12 \
            -export \
            -out "$cert_dir/${cfg.tlsCertificateDomain}.pfx" \
            -inkey "$cert_dir/${cfg.tlsCertificateDomain}.key.pem" \
            -in "$cert_dir/${cfg.tlsCertificateDomain}.crt.pem" \
            -passout pass:

          chmod 0600 "$cert_dir/${cfg.tlsCertificateDomain}."*
        fi
      '';

      serviceConfig = {
        LogsDirectory = "technitium/dns";
        LogsDirectoryMode = "0750";
      }
      // optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "technitium-admin-password:${cfg.adminPasswordFile}" ];
      };
    };

    systemd.services.technitium-dns-configure = mkIf cfg.configureEncryptedDns {
      after = [ "technitium-dns-server.service" ];
      description = "Configure Technitium encrypted DNS listeners";
      wants = [ "technitium-dns-server.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gnugrep
        pkgs.gnused
        pkgs.iproute2
        pkgs.systemd
      ];

      script = ''
        set -euo pipefail

        base="http://127.0.0.1:${toString cfg.webPort}"
        password_file=${adminPasswordFileArg}
        username_file=${adminUsernameFileArg}

        if [ "$password_file" = "" ] || [ ! -r "$password_file" ]; then
          echo "Technitium admin password file is unavailable." >&2
          exit 1
        fi

        admin_password="$(tr -d '\r\n' < "$password_file")"

        if [ "$username_file" = "" ]; then
          admin_user=admin
        elif [ -r "$username_file" ]; then
          admin_user="$(tr -d '\r\n' < "$username_file")"
        else
          echo "Technitium admin username file is unavailable." >&2
          exit 1
        fi

        if [ -z "$admin_user" ]; then
          echo "Technitium admin username is empty." >&2
          exit 1
        fi

        if [ -z "$admin_password" ]; then
          echo "Technitium admin password is empty." >&2
          exit 1
        fi

        for attempt in {1..180}; do
          if curl -fsS "$base/" >/dev/null; then
            break
          fi

          if [ "$attempt" = 180 ]; then
            echo "Timed out waiting for Technitium web API." >&2
            exit 1
          fi

          sleep 1
        done

        login() {
          local username="$1"
          local password="$2"
          curl -fsS --get "$base/api/user/login" \
            --data-urlencode "user=$username" \
            --data-urlencode "pass=$password" \
            | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
        }

        token="$(login "$admin_user" "$admin_password" || true)"
        authenticated_user=$admin_user

        if [ -z "$token" ]; then
          token="$(login admin "$admin_password" || true)"
          authenticated_user=admin
        fi

        if [ -z "$token" ]; then
          token="$(login admin admin || true)"
          authenticated_user=admin
        fi

        if [ -z "$token" ]; then
          echo "Unable to authenticate to Technitium with managed or default admin credentials." >&2
          exit 1
        fi

        api_expect_ok() {
          local label="$1"
          local endpoint="$2"
          shift 2
          local response

          response="$(curl -fsS -X POST "$endpoint" \
            --data-urlencode "token=$token" \
            "$@")"

          if ! echo "$response" | grep -q '"status":"ok"'; then
            echo "Technitium API call failed: $label" >&2
            echo "$response" >&2
            exit 1
          fi
        }

        if [ "$authenticated_user" = admin ]; then
          if [ "$admin_user" = admin ]; then
            api_expect_ok "set admin password" "$base/api/admin/users/set" \
              --data-urlencode "user=admin" \
              --data-urlencode "displayName=Administrator" \
              --data-urlencode "newPass=$admin_password" \
              --data-urlencode "memberOfGroups=Administrators"
          else
            api_expect_ok "rename admin user" "$base/api/admin/users/set" \
              --data-urlencode "user=admin" \
              --data-urlencode "displayName=Administrator" \
              --data-urlencode "newUser=$admin_user" \
              --data-urlencode "newPass=$admin_password" \
              --data-urlencode "memberOfGroups=Administrators"
          fi

          token="$(login "$admin_user" "$admin_password")"
          if [ -z "$token" ]; then
            echo "Unable to authenticate to Technitium with managed admin credentials after migration." >&2
            exit 1
          fi
        fi

        api_expect_ok_or_exists() {
          local label="$1"
          local endpoint="$2"
          shift 2
          local response

          response="$(curl -fsS -X POST "$endpoint" \
            --data-urlencode "token=$token" \
            "$@")"

          if echo "$response" | grep -q '"status":"ok"'; then
            return 0
          fi

          if echo "$response" | grep -qi 'already exists'; then
            return 0
          fi

          echo "Technitium API call failed: $label" >&2
          echo "$response" >&2
          exit 1
        }

        settings_response="$(curl -fsS -X POST "$base/api/settings/set" \
          --data-urlencode "token=$token" \
          --data-urlencode "dnsServerDomain=${cfg.serverDomain}" \
          --data-urlencode "webServiceLocalAddresses=${cfg.webServiceLocalAddresses}" \
          --data-urlencode "webServiceHttpPort=${toString cfg.webPort}" \
          --data-urlencode "webServiceEnableTls=false" \
          --data-urlencode "enableDnsOverTls=${bool true}" \
          --data-urlencode "enableDnsOverHttps=${bool true}" \
          --data-urlencode "dnsOverTlsPort=${toString cfg.dnsOverTlsPort}" \
          --data-urlencode "dnsOverHttpsPort=${toString cfg.httpsPort}" \
          --data-urlencode "dnsTlsCertificatePath=${certificatePath}" \
          --data-urlencode "dnsTlsCertificatePassword=" \
          --data-urlencode "dnsOverHttpRealIpHeader=X-Real-IP")"
        echo "$settings_response" | grep -q '"status":"ok"'

        ${optionalString (localZones != [ ]) localZoneCommands}

        systemctl restart technitium-dns-server.service

        for attempt in {1..180}; do
          if curl -fsS "$base/" >/dev/null \
            && ss -ltn "( sport = :${toString cfg.dnsOverTlsPort} )" | grep -q ":${toString cfg.dnsOverTlsPort}" \
            && ss -ltn "( sport = :${toString cfg.httpsPort} )" | grep -q ":${toString cfg.httpsPort}"; then
            exit 0
          fi

          if [ "$attempt" = 180 ]; then
            echo "Timed out waiting for Technitium encrypted DNS listeners." >&2
            exit 1
          fi

          sleep 1
        done
      '';

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "30s";
        TimeoutStartSec = "5min";
        Type = "oneshot";
      };
    };
  };
}
