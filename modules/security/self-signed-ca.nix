{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.security.selfSignedCA;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.security.selfSignedCA = {
    enable = mkEnableOption "Self-signed Certificate Authority";

    caName = mkOption {
      type = types.str;
      default = "Fleet Internal CA";
      description = "Name of the Certificate Authority";
    };

    domains = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of domains to generate certificates for";
      example = [
        "jenkins.local"
        "grafana.local"
      ];
    };

    validityDays = mkOption {
      type = types.int;
      default = 365;
      description = "Certificate validity in days";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # CA AND CERTIFICATE GENERATION
    # --------------------------------------------------------------------------

    systemd.services.fleet-ca-setup = {
      description = "Setup Fleet Internal Certificate Authority";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        set -euo pipefail

        CA_DIR="/var/lib/fleet-ca"
        CERTS_DIR="$CA_DIR/certs"

        # Create directories
        mkdir -p "$CA_DIR" "$CERTS_DIR"

        # Generate CA private key if it doesn't exist
        if [[ ! -f "$CA_DIR/ca-key.pem" ]]; then
          echo "Generating CA private key..."
          ${pkgs.openssl}/bin/openssl genrsa -out "$CA_DIR/ca-key.pem" 4096
          chmod 600 "$CA_DIR/ca-key.pem"
        fi

        # Generate CA certificate if it doesn't exist
        if [[ ! -f "$CA_DIR/ca-cert.pem" ]]; then
          echo "Generating CA certificate..."
          ${pkgs.openssl}/bin/openssl req -new -x509 -key "$CA_DIR/ca-key.pem" \
            -out "$CA_DIR/ca-cert.pem" -days ${toString cfg.validityDays} \
            -subj "/C=US/ST=Internal/L=Fleet/O=${cfg.caName}/CN=${cfg.caName}"
          chmod 644 "$CA_DIR/ca-cert.pem"
        fi

        # Generate certificates for each domain
        ${concatMapStringsSep "\n" (domain: ''
                    DOMAIN_DIR="$CERTS_DIR/${domain}"
                    mkdir -p "$DOMAIN_DIR"

                    # Generate domain private key
                    if [[ ! -f "$DOMAIN_DIR/key.pem" ]]; then
                      echo "Generating private key for ${domain}..."
                      ${pkgs.openssl}/bin/openssl genrsa -out "$DOMAIN_DIR/key.pem" 2048
                      chmod 600 "$DOMAIN_DIR/key.pem"
                    fi

                    # Generate certificate signing request
                    if [[ ! -f "$DOMAIN_DIR/cert.pem" ]]; then
                      echo "Generating certificate for ${domain}..."
                      ${pkgs.openssl}/bin/openssl req -new -key "$DOMAIN_DIR/key.pem" \
                        -out "$DOMAIN_DIR/csr.pem" \
                        -subj "/C=US/ST=Internal/L=Fleet/O=Fleet Services/CN=${domain}"

                      # Sign the certificate with our CA
                      ${pkgs.openssl}/bin/openssl x509 -req -in "$DOMAIN_DIR/csr.pem" \
                        -CA "$CA_DIR/ca-cert.pem" -CAkey "$CA_DIR/ca-key.pem" \
                        -CAcreateserial -out "$DOMAIN_DIR/cert.pem" \
                        -days ${toString cfg.validityDays} \
                        -extensions v3_req -extfile <(cat <<EOF
          [v3_req]
          keyUsage = keyEncipherment, dataEncipherment
          extendedKeyUsage = serverAuth
          subjectAltName = DNS:${domain}
          EOF
                      )

                      # Clean up CSR
                      rm "$DOMAIN_DIR/csr.pem"
                      chmod 644 "$DOMAIN_DIR/cert.pem"
                    fi

                    # Set ownership for nginx
                    chown -R nginx:nginx "$DOMAIN_DIR"
        '') cfg.domains}

        echo "Fleet CA setup complete!"
        echo "CA certificate available at: $CA_DIR/ca-cert.pem"
        echo "To trust this CA, add the CA certificate to your browser/system trust store."
      '';
    };

    # --------------------------------------------------------------------------
    # CERTIFICATE STORE
    # --------------------------------------------------------------------------

    # Create a placeholder CA certificate for build time
    environment.etc."fleet-ca-placeholder.pem".text = ''
      -----BEGIN CERTIFICATE-----
      MIIBkTCB+wIJANK4bX0QRtlbMA0GCSqGSIb3DQEBCwUAMBQxEjAQBgNVBAMMCVRl
      c3QgUGxhY2UwHhcNMjMwMTAxMDAwMDAwWhcNMjQwMTAxMDAwMDAwWjAUMRIwEAYD
      VQQDDAlUZXN0IFBsYWNlMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANK4bX0QRtlb
      -----END CERTIFICATE-----
    '';

    # Use a systemd path unit to dynamically add the real CA when it's created
    systemd.paths.fleet-ca-trust = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "/var/lib/fleet-ca/ca-cert.pem";
      };
    };

    systemd.services.fleet-ca-trust = {
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Copy the real CA certificate to the system trust store
        mkdir -p /etc/ssl/certs/fleet
        cp /var/lib/fleet-ca/ca-cert.pem /etc/ssl/certs/fleet/ca-cert.pem

        # Update the CA bundle
        ${pkgs.cacert}/bin/update-ca-certificates || true
      '';
    };

    # --------------------------------------------------------------------------
    # USERS AND GROUPS
    # --------------------------------------------------------------------------

    users.users.nginx = {
      isSystemUser = true;
      group = "nginx";
    };

    users.groups.nginx = { };
  };
}
