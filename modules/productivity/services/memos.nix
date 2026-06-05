{
  config,
  lib,
  pkgs,
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
    memosGid
    memosUid
    serviceHosts
    ;
  oidcCfg = cfg.memos.oidc;
  memosOidcPayload = pkgs.writeText "memos-oidc-provider.json" (
    builtins.toJSON {
      type = "OAUTH2";
      title = oidcCfg.displayName;
      identifierFilter = oidcCfg.identifierFilter;
      config.oauth2Config = {
        clientId = oidcCfg.clientId;
        authUrl = oidcCfg.authUrl;
        tokenUrl = oidcCfg.tokenUrl;
        userInfoUrl = oidcCfg.userInfoUrl;
        scopes = oidcCfg.scopes;
        fieldMapping = {
          identifier = oidcCfg.fieldMapping.identifier;
          displayName = oidcCfg.fieldMapping.displayName;
          email = oidcCfg.fieldMapping.email;
          avatarUrl = oidcCfg.fieldMapping.avatarUrl;
        };
      };
    }
  );
  memosOidcProvision = pkgs.writeShellScript "memos-oidc-provision" ''
    set -euo pipefail

    ${lib.getExe pkgs.python3} - <<'PY'
    import json
    import sys
    import time
    import urllib.error
    import urllib.parse
    import urllib.request
    from pathlib import Path

    api_base = "${removeSuffix "/" oidcCfg.apiBaseUrl}"
    provider_uid = "${oidcCfg.providerUid}"
    provider_name = f"identity-providers/{provider_uid}"
    token_path = Path("${oidcCfg.adminTokenFile}")
    secret_path = Path("${oidcCfg.clientSecretFile}")

    with open("${memosOidcPayload}", "r", encoding="utf-8") as payload_file:
        payload = json.load(payload_file)

    admin_token = token_path.read_text(encoding="utf-8").strip()
    client_secret = secret_path.read_text(encoding="utf-8").strip()
    if not admin_token:
        raise SystemExit("Memos admin PAT is empty")
    if not client_secret:
        raise SystemExit("Memos OIDC client secret is empty")

    payload["config"]["oauth2Config"]["clientSecret"] = client_secret

    def request(method, path, body=None):
        data = None if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
        req = urllib.request.Request(
            f"{api_base}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {admin_token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.status, response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode("utf-8", errors="replace")

    for attempt in range(30):
        status, _body = request("GET", "/api/v1/identity-providers")
        if status == 200:
            break
        if attempt == 29:
            raise SystemExit(f"Memos API did not become ready; last status {status}")
        time.sleep(2)

    status, _body = request("GET", f"/api/v1/{provider_name}")
    if status == 200:
        status, body = request("PATCH", f"/api/v1/{provider_name}", payload)
        action = "updated"
    elif status == 404:
        query = urllib.parse.urlencode({"identity_provider_id": provider_uid})
        status, body = request("POST", f"/api/v1/identity-providers?{query}", payload)
        action = "created"
    else:
        raise SystemExit(f"failed to inspect Memos identity provider {provider_name}: HTTP {status}")

    if status not in (200, 201):
        print(body, file=sys.stderr)
        raise SystemExit(f"failed to provision Memos identity provider {provider_name}: HTTP {status}")

    print(f"{action} Memos identity provider {provider_name}")
    PY
  '';
in
{
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !oidcCfg.enable || oidcCfg.adminTokenFile != null;
        message = "fleet.productivity.stack.memos.oidc.adminTokenFile must be set when Memos OIDC is enabled.";
      }
      {
        assertion = !oidcCfg.enable || oidcCfg.clientSecretFile != null;
        message = "fleet.productivity.stack.memos.oidc.clientSecretFile must be set when Memos OIDC is enabled.";
      }
    ];

    virtualisation.oci-containers.containers.memos = {
      image = "docker.io/neosmemo/memos@sha256:62896725e9f84cc1c6afa6319f8ac759bc7d64670a9e003ef0844c12d345eadb";
      pull = "missing";

      environment = {
        MEMOS_ADDR = "0.0.0.0";
        MEMOS_DATA = "/var/opt/memos";
        MEMOS_DRIVER = "sqlite";
        MEMOS_GID = toString memosGid;
        MEMOS_INSTANCE_URL = "https://${serviceHosts.memos}";
        MEMOS_MODE = "prod";
        MEMOS_PORT = toString cfg.ports.memos;
        MEMOS_UID = toString memosUid;
      };

      extraOptions = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--user=${toString memosUid}:${toString memosGid}"
      ];

      ports = [
        "0.0.0.0:${toString cfg.ports.memos}:${toString cfg.ports.memos}/tcp"
      ];

      volumes = [
        "${appdata}/memos:/var/opt/memos"
      ];
    };

    systemd.services.podman-memos = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.services.memos-oidc-config = mkIf oidcCfg.enable {
      description = "Configure Memos Authentik OAuth2 identity provider";
      after = [
        "network-online.target"
        "podman-memos.service"
      ];
      requires = [ "podman-memos.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [
        memosOidcPayload
        memosOidcProvision
      ];
      serviceConfig = {
        ExecStart = memosOidcProvision;
        Group = "memos";
        RemainAfterExit = true;
        Type = "oneshot";
        User = "memos";
      };
    };
  };
}
