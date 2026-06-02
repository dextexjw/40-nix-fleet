{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.monitoring.checkmateProvisioning;
  jsonFormat = pkgs.formats.json { };

  targets = {
    inherit (cfg) managedTag;
    expectedHardwareMonitors = length cfg.hardwareMonitors;
    expectedManagedMonitors = length cfg.serviceMonitors + length cfg.hardwareMonitors;
    expectedServiceMonitors = length cfg.serviceMonitors;
    hardwareMonitors = cfg.hardwareMonitors;
    serviceMonitors = cfg.serviceMonitors;
  };

  targetsFile = jsonFormat.generate "checkmate-targets.json" targets;

  provisioningScript = pkgs.writeTextFile {
    name = "checkmate-provisioning";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import json
      import os
      import sys
      import time
      import urllib.error
      import urllib.parse
      import urllib.request


      class ApiError(Exception):
          def __init__(self, message, retryable=False):
              super().__init__(message)
              self.retryable = retryable


      def fail(message):
          print(f"error: {message}", file=sys.stderr)
          sys.exit(1)


      base_url = os.environ.get("CHECKMATE_BASE_URL", "").rstrip("/")
      targets_path = os.environ.get("CHECKMATE_TARGETS_FILE", "")
      summary_path = os.environ.get("CHECKMATE_SUMMARY_FILE", "")
      email = os.environ.get("CHECKMATE_EMAIL", "")
      password = os.environ.get("CHECKMATE_PASSWORD", "")
      capture_secret = os.environ.get("API_SECRET", "")

      if not base_url:
          fail("CHECKMATE_BASE_URL is unset")
      if not targets_path:
          fail("CHECKMATE_TARGETS_FILE is unset")
      if not email or not password:
          fail("CHECKMATE_EMAIL and CHECKMATE_PASSWORD must be set")
      if not capture_secret:
          fail("API_SECRET must be set by the Checkmate Capture environment file")


      def load_targets(path):
          with open(path, "r", encoding="utf-8") as handle:
              return json.load(handle)


      target_data = load_targets(targets_path)
      managed_tag = target_data["managedTag"]
      service_monitors = target_data["serviceMonitors"]
      hardware_monitors = target_data["hardwareMonitors"]


      def request_once(method, path, body=None, token=None):
          data = None
          headers = {"Accept": "application/json"}
          if body is not None:
              data = json.dumps(body, sort_keys=True).encode("utf-8")
              headers["Content-Type"] = "application/json"
          if token:
              headers["Authorization"] = f"Bearer {token}"

          req = urllib.request.Request(
              f"{base_url}{path}",
              data=data,
              headers=headers,
              method=method,
          )
          try:
              with urllib.request.urlopen(req, timeout=30) as response:
                  payload = response.read().decode("utf-8")
          except urllib.error.HTTPError as error:
              detail = error.read().decode("utf-8", errors="replace")
              retryable = error.code in (502, 503, 504)
              raise ApiError(f"{method} {path} returned HTTP {error.code}: {detail}", retryable)
          except urllib.error.URLError as error:
              raise ApiError(f"{method} {path} failed: {error}", True)

          if not payload:
              return {}
          return json.loads(payload)


      def request(method, path, body=None, token=None):
          try:
              return request_once(method, path, body=body, token=token)
          except ApiError as error:
              fail(str(error))


      def response_data(response):
          if isinstance(response, dict) and "data" in response:
              return response["data"]
          return response


      def monitor_id(monitor):
          return monitor.get("id") or monitor.get("_id")


      def monitor_tags(monitor):
          tags = monitor.get("tags") or []
          return tags if isinstance(tags, list) else []


      def identity_from_tags(tags):
          identities = [
              tag for tag in tags
              if tag.startswith("fleet-service:") or tag.startswith("fleet-host:")
          ]
          return identities[0] if identities else None


      def managed_description(identity, description):
          return "\n".join([
              f"fleet-managed: {managed_tag}",
              f"fleet-identity: {identity}",
              "",
              description or "",
          ]).rstrip()


      def identity_from_description(description):
          if not isinstance(description, str):
              return None
          for line in description.splitlines():
              if not line.startswith("fleet-identity: "):
                  continue
              identity = line.split(": ", 1)[1].strip()
              if identity.startswith("fleet-service:") or identity.startswith("fleet-host:"):
                  return identity
          return None


      def is_managed_description(description):
          if not isinstance(description, str):
              return False
          return f"fleet-managed: {managed_tag}" in description.splitlines()


      def identity_from_monitor(monitor):
          return identity_from_tags(monitor_tags(monitor)) or identity_from_description(monitor.get("description"))


      def login():
          login_body = {
              "email": email,
              "password": password,
          }
          last_error = None
          for attempt in range(1, 31):
              try:
                  payload = response_data(request_once("POST", "/auth/login", login_body))
                  break
              except ApiError as error:
                  last_error = error
                  if not error.retryable:
                      fail(str(error))
                  if attempt == 30:
                      fail(str(last_error))
                  time.sleep(2)
          else:
              fail(str(last_error))
          token = payload.get("token") if isinstance(payload, dict) else None
          if not token:
              fail("Checkmate login did not return an auth token")
          return token


      def list_monitors(token):
          payload = response_data(request("GET", "/monitors/team", token=token))
          if payload is None:
              return []
          if isinstance(payload, list):
              return payload
          if isinstance(payload, dict):
              if isinstance(payload.get("monitors"), list):
                  return payload["monitors"]
              if isinstance(payload.get("items"), list):
                  return payload["items"]
          fail("Checkmate monitors response had an unexpected shape")


      def build_service_body(target):
          identity = f"fleet-service:{target['id']}"
          tags = [
              managed_tag,
              identity,
              f"fleet-group:{target['group']}",
          ]
          body = {
              "description": managed_description(identity, target["description"]),
              "group": target["group"],
              "interval": target["interval"],
              "isActive": True,
              "name": target["name"],
              "statusWindowSize": 5,
              "statusWindowThreshold": 60,
              "tags": tags,
              "type": target["type"],
              "url": target["url"],
          }
          if target["type"] == "http":
              body.update({
                  "ignoreTlsErrors": False,
                  "useAdvancedMatching": False,
              })
          elif target["type"] == "port":
              body["port"] = target["port"]
          else:
              fail(f"unsupported service monitor type {target['type']!r}")
          return identity, body


      def build_hardware_body(target):
          identity = f"fleet-host:{target['id']}"
          body = {
              "cpuAlertThreshold": 100,
              "description": managed_description(identity, target["description"]),
              "diskAlertThreshold": 100,
              "group": target["group"],
              "interval": target["interval"],
              "isActive": True,
              "memoryAlertThreshold": 100,
              "name": target["name"],
              "secret": capture_secret,
              "statusWindowSize": 5,
              "statusWindowThreshold": 60,
              "tags": [
                  managed_tag,
                  identity,
                  f"fleet-group:{target['group']}",
              ],
              "tempAlertThreshold": 100,
              "type": "hardware",
              "url": target["url"],
          }
          return identity, body


      def comparable(body):
          skipped = {"isActive", "secret", "tags"}
          return {
              key: value
              for key, value in body.items()
              if key not in skipped
          }


      def monitor_matches(existing, desired):
          expected = comparable(desired)
          actual = {
              key: existing.get(key)
              for key in expected.keys()
          }
          return actual == expected


      def patch_body(body):
          return {
              key: value
              for key, value in body.items()
              if key != "isActive"
          }


      def bulk_pause(token, ids, pause):
          if not ids:
              return 0
          request("POST", "/monitors/bulk/pause", {
              "monitorIds": ids,
              "pause": pause,
          }, token=token)
          return len(ids)


      token = login()
      existing_monitors = list_monitors(token)
      desired = dict(build_service_body(target) for target in service_monitors)
      desired.update(dict(build_hardware_body(target) for target in hardware_monitors))


      def matches_adoption_candidate(existing, desired_body):
          if existing.get("name") != desired_body["name"]:
              return False
          if existing.get("type") != desired_body["type"]:
              return False
          if desired_body["type"] == "port":
              return existing.get("url") == desired_body["url"] and existing.get("port") == desired_body["port"]
          if desired_body["type"] == "hardware":
              current_url = existing.get("url")
              metrics_url = desired_body["url"]
              return current_url == metrics_url or f"{current_url}/api/v1/metrics" == metrics_url
          return existing.get("url") == desired_body["url"]


      def adoption_identity(existing):
          matches = [
              identity for identity, body in desired.items()
              if matches_adoption_candidate(existing, body)
          ]
          return matches[0] if len(matches) == 1 else None


      existing_by_identity = {}
      duplicate_ids = []
      stale_ids = []
      managed_existing_count = 0
      adopted_existing_count = 0
      for monitor in existing_monitors:
          mid = monitor_id(monitor)
          if not mid:
              continue
          identity = identity_from_monitor(monitor)
          explicit_managed = managed_tag in monitor_tags(monitor) or is_managed_description(monitor.get("description"))
          if identity is None and not explicit_managed:
              identity = adoption_identity(monitor)
              if identity is not None:
                  adopted_existing_count += 1
          elif explicit_managed:
              managed_existing_count += 1

          if identity is None and explicit_managed:
              stale_ids.append(mid)
              continue
          if identity is None:
              continue
          if identity in existing_by_identity:
              duplicate_ids.append(mid)
          else:
              existing_by_identity[identity] = monitor

      created = 0
      updated = 0
      desired_existing_ids = []
      desired_inactive_ids = []

      for identity, body in desired.items():
          existing = existing_by_identity.get(identity)
          if existing is None:
              request("POST", "/monitors", body, token=token)
              created += 1
              continue

          mid = monitor_id(existing)
          desired_existing_ids.append(mid)
          if not existing.get("isActive", True):
              desired_inactive_ids.append(mid)

          force_patch = body["type"] == "hardware"
          if force_patch or not monitor_matches(existing, body):
              request("PATCH", f"/monitors/{urllib.parse.quote(mid)}", patch_body(body), token=token)
              updated += 1

      stale_identity_ids = [
          monitor_id(monitor)
          for identity, monitor in existing_by_identity.items()
          if identity not in desired and monitor_id(monitor)
      ]
      pause_ids = []
      for mid in stale_ids + duplicate_ids + stale_identity_ids:
          if mid not in pause_ids:
              pause_ids.append(mid)

      paused_stale = bulk_pause(token, pause_ids, True)
      resumed = bulk_pause(token, desired_inactive_ids, False)

      summary = {
          "created": created,
          "expectedHardwareMonitors": target_data["expectedHardwareMonitors"],
          "expectedManagedMonitors": target_data["expectedManagedMonitors"],
          "expectedServiceMonitors": target_data["expectedServiceMonitors"],
          "adoptedExisting": adopted_existing_count,
          "managedExisting": managed_existing_count,
          "pausedStale": paused_stale,
          "resumed": resumed,
          "updated": updated,
      }

      summary_text = json.dumps(summary, sort_keys=True)
      print(summary_text)

      if summary_path:
          with open(summary_path, "w", encoding="utf-8") as handle:
              handle.write(summary_text + "\n")
    '';
  };
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.monitoring.checkmateProvisioning = {
    enable = mkEnableOption "declarative Checkmate monitor provisioning";

    baseUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:52345/api/v1";
      description = "Checkmate API base URL used by checkmate-provisioning.service.";
    };

    captureEnvironmentFile = mkOption {
      type = types.path;
      default = "/run/secrets/checkmate-capture-environment";
      description = "Runtime environment file containing the Checkmate Capture API_SECRET.";
    };

    credentialsFile = mkOption {
      type = types.path;
      default = "/run/secrets/checkmate-provisioning-credentials";
      description = "Runtime environment file containing CHECKMATE_EMAIL and CHECKMATE_PASSWORD.";
    };

    hardwareMonitors = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            description = mkOption { type = types.str; };
            group = mkOption { type = types.str; };
            id = mkOption { type = types.str; };
            interval = mkOption { type = types.ints.positive; };
            name = mkOption { type = types.str; };
            url = mkOption { type = types.str; };
          };
        }
      );
      default = [ ];
      description = "Generated Checkmate hardware monitor targets.";
    };

    managedTag = mkOption {
      type = types.str;
      default = "fleet-declared";
      description = "Tag used to identify Checkmate monitors managed by this module.";
    };

    serviceMonitors = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            description = mkOption { type = types.str; };
            group = mkOption { type = types.str; };
            id = mkOption { type = types.str; };
            interval = mkOption { type = types.ints.positive; };
            name = mkOption { type = types.str; };
            port = mkOption {
              type = types.nullOr types.port;
              default = null;
            };
            type = mkOption {
              type = types.enum [
                "http"
                "port"
              ];
            };
            url = mkOption { type = types.str; };
          };
        }
      );
      default = [ ];
      description = "Generated Checkmate service monitor targets.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    environment.etc."fleet/checkmate-targets.json".source = targetsFile;

    systemd.services.checkmate-provisioning = {
      description = "Provision Checkmate monitors from the fleet exposure catalog";
      after = [
        "checkmate-capture.service"
        "network-online.target"
        "podman-checkmate-mongodb.service"
        "podman-checkmate.service"
      ];
      requires = [
        "podman-checkmate-mongodb.service"
        "podman-checkmate.service"
      ];
      wants = [
        "checkmate-capture.service"
        "network-online.target"
      ];
      serviceConfig = {
        Environment = [
          "CHECKMATE_BASE_URL=${cfg.baseUrl}"
          "CHECKMATE_SUMMARY_FILE=/var/lib/checkmate-provisioning/last-summary.json"
          "CHECKMATE_TARGETS_FILE=/etc/fleet/checkmate-targets.json"
        ];
        EnvironmentFile = [
          cfg.credentialsFile
          cfg.captureEnvironmentFile
        ];
        ExecStart = provisioningScript;
        Group = "root";
        NoNewPrivileges = true;
        PrivateTmp = true;
        StateDirectory = "checkmate-provisioning";
        Type = "oneshot";
        UMask = "0077";
        User = "root";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
