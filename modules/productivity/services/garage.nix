{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib)
    cfg
    appdata
    garageEnvironmentFile
    secretPath
    serviceHosts
    ;
  kaneoUploadsCfg = cfg.garage.kaneoUploads;
  planeUploadsCfg = cfg.garage.planeUploads;
  mkUploadsCorsConfig =
    name: uploadsCfg:
    pkgs.writeText "${name}-garage-cors.xml" ''
      <CORSConfiguration>
        <CORSRule>
          <AllowedOrigin>${uploadsCfg.corsAllowedOrigin}</AllowedOrigin>
          <AllowedMethod>GET</AllowedMethod>
          <AllowedMethod>HEAD</AllowedMethod>
          <AllowedMethod>POST</AllowedMethod>
          <AllowedMethod>PUT</AllowedMethod>
          <AllowedHeader>*</AllowedHeader>
          <ExposeHeader>ETag</ExposeHeader>
          <MaxAgeSeconds>3000</MaxAgeSeconds>
        </CORSRule>
      </CORSConfiguration>
    '';
  mkGarageBucketService =
    name: label: uploadsCfg:
    let
      corsConfig = mkUploadsCorsConfig name uploadsCfg;
    in
    mkIf uploadsCfg.enable {
      description = "Provision Garage bucket and key for ${label} uploads";
      after = [ "garage.service" ];
      requires = [ "garage.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.diffutils
        pkgs.garage
        pkgs.gnugrep
        pkgs.s3cmd
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "garage";
        Group = "garage";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        access_key_id_file=${escapeShellArg uploadsCfg.accessKeyIdFile}
        secret_access_key_file=${escapeShellArg uploadsCfg.secretAccessKeyFile}
        bucket=${escapeShellArg uploadsCfg.bucket}
        key_name=${escapeShellArg uploadsCfg.keyName}
        endpoint_url=${escapeShellArg uploadsCfg.endpointUrl}
        cors_config=${escapeShellArg corsConfig}

        if [ ! -r "$access_key_id_file" ]; then
          echo "$access_key_id_file is not readable; refusing to provision ${label} Garage key" >&2
          exit 1
        fi
        if [ ! -r "$secret_access_key_file" ]; then
          echo "$secret_access_key_file is not readable; refusing to provision ${label} Garage key" >&2
          exit 1
        fi

        IFS= read -r access_key_id < "$access_key_id_file" || [ -n "$access_key_id" ]
        IFS= read -r secret_access_key < "$secret_access_key_file" || [ -n "$secret_access_key" ]
        if [ -z "$access_key_id" ] || [ -z "$secret_access_key" ]; then
          echo "${label} Garage credentials must not be empty" >&2
          exit 1
        fi

        if ! garage key info "$access_key_id" >/dev/null 2>&1; then
          if garage key info "$key_name" >/dev/null 2>&1; then
            echo "Garage key name $key_name already exists with a different access key ID; refusing to overwrite it" >&2
            exit 1
          fi
          garage key import --yes -n "$key_name" "$access_key_id" "$secret_access_key"
        fi

        garage bucket info "$bucket" >/dev/null 2>&1 || garage bucket create "$bucket"
        garage bucket allow --read --write --owner "$bucket" --key "$access_key_id"

        s3cmd_config="$(mktemp)"
        src="$(mktemp)"
        dst="$(mktemp)"
        headers="$(mktemp)"
        body="$(mktemp)"
        trap 'rm -f "$s3cmd_config" "$src" "$dst" "$headers" "$body"' EXIT
        chmod 0600 "$s3cmd_config"
        {
          printf '%s\n' '[default]'
          printf 'access_key = %s\n' "$access_key_id"
          printf 'secret_key = %s\n' "$secret_access_key"
          printf 'host_base = 127.0.0.1:%s\n' ${escapeShellArg (toString cfg.ports.garageS3)}
          printf 'host_bucket = 127.0.0.1:%s/%%(bucket)\n' ${escapeShellArg (toString cfg.ports.garageS3)}
          printf '%s\n' 'use_https = False'
          printf '%s\n' 'signature_v2 = False'
          printf '%s\n' 'bucket_location = garage'
        } > "$s3cmd_config"

        s3cmd --config "$s3cmd_config" --quiet setcors "$cors_config" "s3://$bucket"
        garage bucket deny --owner "$bucket" --key "$access_key_id"
        s3cmd --config "$s3cmd_config" --quiet ls "s3://$bucket" >/dev/null

        smoke_object=".${name}-garage-smoke"
        printf '%s\n' "${label} Garage smoke" > "$src"
        s3cmd --config "$s3cmd_config" --quiet put "$src" "s3://$bucket/$smoke_object"
        s3cmd --config "$s3cmd_config" --quiet get --force "s3://$bucket/$smoke_object" "$dst"
        cmp -s "$src" "$dst"
        s3cmd --config "$s3cmd_config" --quiet del "s3://$bucket/$smoke_object" >/dev/null

        status="$(curl -sS -D "$headers" -o "$body" -w "%{http_code}" \
          --max-time 10 \
          -X OPTIONS \
          -H "Origin: ${uploadsCfg.corsAllowedOrigin}" \
          -H "Access-Control-Request-Method: PUT" \
          -H "Access-Control-Request-Headers: content-type" \
          "$endpoint_url/$bucket/.${name}-cors-check")"
        case "$status" in
          2*) ;;
          *)
            echo "unexpected ${label} Garage CORS status $status" >&2
            cat "$body" >&2
            exit 1
            ;;
        esac
        tr -d '\r' < "$headers" | grep -Fqi "access-control-allow-origin: ${uploadsCfg.corsAllowedOrigin}"
      '';
    };
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.garage
      pkgs.s3cmd
    ];

    services.garage = {
      enable = true;
      environmentFile = garageEnvironmentFile;
      package = pkgs.garage;
      settings = {
        replication_factor = 1;
        consistency_mode = "consistent";
        metadata_dir = "${appdata}/garage/meta";
        data_dir = "${appdata}/garage/data";
        metadata_snapshots_dir = "${appdata}/garage/snapshots";
        db_engine = "lmdb";
        rpc_bind_addr = "0.0.0.0:${toString cfg.ports.garageRpc}";
        rpc_public_addr = "127.0.0.1:${toString cfg.ports.garageRpc}";
        rpc_secret_file = secretPath "garage-rpc-secret";
        s3_api = {
          api_bind_addr = "0.0.0.0:${toString cfg.ports.garageS3}";
          root_domain = ".${serviceHosts.garage}";
          s3_region = "garage";
        };
        s3_web = {
          bind_addr = "0.0.0.0:${toString cfg.ports.garageWeb}";
          root_domain = ".${serviceHosts.garageWeb}";
        };
        admin = {
          admin_token_file = secretPath "garage-admin-token";
          api_bind_addr = "127.0.0.1:${toString cfg.ports.garageAdmin}";
          metrics_require_token = true;
          metrics_token_file = secretPath "garage-metrics-token";
        };
      };
    };

    systemd.services.garage.serviceConfig = {
      DynamicUser = mkForce false;
      User = "garage";
      Group = "garage";
    };

    systemd.services = {
      garage-kaneo-bucket = mkGarageBucketService "kaneo" "Kaneo" kaneoUploadsCfg;
      garage-plane-bucket = mkGarageBucketService "plane" "Plane" planeUploadsCfg;
    };
  };
}
