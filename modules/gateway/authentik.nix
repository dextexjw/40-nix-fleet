{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.authentik;
  postgresqlDataDir = "${cfg.stateDir}/postgresql/${config.services.postgresql.package.psqlSchema}";
  redisDataDir = "${cfg.stateDir}/redis";
  secretFile = path: if path == null then "/run/secrets/UNSET" else path;
  authentikEnvironment = {
    AUTHENTIK_CERT_DISCOVERY_DIR = "${cfg.stateDir}/certs";
    AUTHENTIK_DISABLE_STARTUP_ANALYTICS = "true";
    AUTHENTIK_DISABLE_UPDATE_CHECK = "true";
    AUTHENTIK_ERROR_REPORTING__ENABLED = "false";
    AUTHENTIK_LISTEN__HTTP = "${cfg.listenAddress}:${toString cfg.httpPort}";
    AUTHENTIK_LISTEN__HTTPS = "${cfg.listenAddress}:9443";
    AUTHENTIK_LISTEN__METRICS = "${cfg.listenAddress}:${toString cfg.metricsPort}";
    AUTHENTIK_LOG_LEVEL = "info";
    AUTHENTIK_POSTGRESQL__HOST = "127.0.0.1";
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_POSTGRESQL__PORT = "5432";
    AUTHENTIK_POSTGRESQL__USER = "authentik";
    AUTHENTIK_POSTGRESQL__CONN_MAX_AGE = "0";
    AUTHENTIK_STORAGE__FILE__PATH = "${cfg.stateDir}/media";
  };

  authentikWrapper = pkgs.writeShellScript "fleet-authentik" ''
    set -euo pipefail

    export AUTHENTIK_SECRET_KEY="$(<${secretFile cfg.secretKeyFile})"
    export AUTHENTIK_POSTGRESQL__PASSWORD="$(<${secretFile cfg.postgresql.passwordFile})"

    if [ -n "${cfg.bootstrap.email}" ]; then
      export AUTHENTIK_BOOTSTRAP_EMAIL="${cfg.bootstrap.email}"
    fi

    ${lib.optionalString (cfg.bootstrap.username != null) ''
      export AUTHENTIK_BOOTSTRAP_USERNAME="${cfg.bootstrap.username}"
    ''}

    if [ -r "${secretFile cfg.bootstrap.passwordFile}" ]; then
      export AUTHENTIK_BOOTSTRAP_PASSWORD="$(<${secretFile cfg.bootstrap.passwordFile})"
    fi

    if [ -r "${secretFile cfg.bootstrap.tokenFile}" ]; then
      export AUTHENTIK_BOOTSTRAP_TOKEN="$(<${secretFile cfg.bootstrap.tokenFile})"
    fi

    exec ${lib.getExe cfg.package} "$@"
  '';

  groupProvisioningJson = pkgs.writeText "fleet-authentik-groups.json" (
    builtins.toJSON {
      groups = cfg.groups;
    }
  );

  applicationProvisioningJson = pkgs.writeText "fleet-authentik-applications.json" (
    builtins.toJSON {
      adminGroups = cfg.adminGroups;
      applications = cfg.applications;
      bootstrapEmail = cfg.bootstrap.email;
      bootstrapUsername = cfg.bootstrap.username;
    }
  );

  provisioningPython = pkgs.writeText "fleet-authentik-provision.py" ''
    import json
    import os

    from django.db import transaction

    from authentik.core.models import Application, Group, PropertyMapping, User
    from authentik.flows.models import Flow
    from authentik.outposts.models import Outpost
    from authentik.policies.models import PolicyBinding, PolicyEngineMode
    from authentik.providers.oauth2.constants import SubModes
    from authentik.providers.oauth2.models import (
        ClientTypes,
        OAuth2Provider,
        RedirectURI,
        RedirectURIMatchingMode,
        ScopeMapping,
    )
    from authentik.providers.proxy.models import ProxyProvider

    with open("${groupProvisioningJson}", "r", encoding="utf-8") as groups_file:
        declared_groups = json.load(groups_file)["groups"]

    with open("${applicationProvisioningJson}", "r", encoding="utf-8") as applications_file:
        application_config = json.load(applications_file)
        declared_admin_groups = application_config["adminGroups"]
        declared_applications = application_config["applications"]
        bootstrap_email = application_config["bootstrapEmail"]
        bootstrap_username = application_config["bootstrapUsername"]
        bootstrap_password = os.environ.get("AUTHENTIK_BOOTSTRAP_PASSWORD")


    def ensure_group(name):
        group, created = Group.objects.update_or_create(
            name=name,
            defaults={"is_superuser": False},
        )
        print(f"{'created' if created else 'updated'} group {name}")
        return group


    def ensure_superuser_group(name):
        group, created = Group.objects.update_or_create(
            name=name,
            defaults={"is_superuser": True},
        )
        print(f"{'created' if created else 'updated'} superuser group {name}")
        return group


    def ensure_flow(slug, designation, name, title, authentication):
        flow, created = Flow.objects.update_or_create(
            slug=slug,
            defaults={
                "designation": designation,
                "name": name,
                "title": title,
                "authentication": authentication,
            },
        )
        print(f"{'created' if created else 'updated'} flow {slug}")
        return flow


    def ensure_bootstrap_admin_groups():
        if not bootstrap_email and not bootstrap_username:
            return
        username = bootstrap_username or bootstrap_email.split("@", 1)[0]
        user = User.objects.filter(username=username).first()
        if user is None and bootstrap_email:
            user = User.objects.filter(email=bootstrap_email).first()
        created = user is None
        if user is None:
            user = User(username=username)
        user.username = username
        if bootstrap_email:
            user.email = bootstrap_email
        user.name = "Fleet Bootstrap Admin"
        user.is_active = True
        user.is_superuser = True
        if bootstrap_password:
            user.set_password(bootstrap_password)
        user.save()
        groups = [ensure_superuser_group("authentik Admins")]
        groups.extend(ensure_group(group_name) for group_name in declared_admin_groups)
        user.ak_groups.add(*groups)
        print(f"{'created' if created else 'updated'} bootstrap admin user {user.username}")


    def remove_stale_proxy_providers(desired_provider_names):
        stale_providers = list(ProxyProvider.objects.filter(name__startswith="fleet-").exclude(name__in=desired_provider_names))
        if not stale_providers:
            return
        provider_ids = [provider.pk for provider in stale_providers]
        stale_applications = list(Application.objects.filter(provider_id__in=provider_ids))
        outposts = Outpost.objects.filter(providers__pk__in=provider_ids).distinct()
        for outpost in outposts:
            outpost.providers.remove(*stale_providers)
        for application in stale_applications:
            print(f"deleted proxy application {application.slug}")
            application.delete()
        for provider in stale_providers:
            print(f"deleted proxy provider {provider.name}")
            provider.delete()


    def oidc_scope_mappings():
        managed_ids = [
            "goauthentik.io/providers/oauth2/scope-openid",
            "goauthentik.io/providers/oauth2/scope-profile",
        ]
        email_mapping, _ = ScopeMapping.objects.update_or_create(
            managed="goauthentik.io/fleet/providers/oauth2/scope-email-verified",
            defaults={
                "name": "Fleet OAuth Mapping: verified email",
                "scope_name": "email",
                "description": "Email address",
                "expression": "return {\"email\": request.user.email, \"email_verified\": True}",
            },
        )
        mappings = list(PropertyMapping.objects.filter(managed__in=managed_ids))
        mappings.append(email_mapping)
        return mappings


    def read_secret(path, slug):
        if not path:
            raise ValueError(f"native OIDC application {slug} does not declare clientSecretFile")
        with open(path, "r", encoding="utf-8") as secret_file:
            value = secret_file.read().strip()
        if not value:
            raise ValueError(f"native OIDC application {slug} has an empty client secret")
        return value


    def ensure_oidc_provider(app, authorization_flow, invalidation_flow, mappings):
        slug = app["slug"]
        oidc = app.get("oidc") or {}
        redirect_uris = oidc.get("redirectUris") or []
        if not redirect_uris:
            raise ValueError(f"native OIDC application {slug} does not declare redirectUris")

        provider_name = f"fleet-{slug}-oidc"
        provider = OAuth2Provider.objects.filter(name=provider_name).first()
        created = provider is None
        if provider is None:
            provider = OAuth2Provider(name=provider_name)

        provider.authorization_flow = authorization_flow
        provider.invalidation_flow = invalidation_flow
        provider.client_type = oidc.get("clientType") or ClientTypes.CONFIDENTIAL
        provider.client_id = oidc.get("clientId") or slug
        provider.client_secret = read_secret(oidc.get("clientSecretFile"), slug)
        provider.include_claims_in_id_token = oidc.get("includeClaimsInIdToken", True)
        provider.sub_mode = oidc.get("subMode") or SubModes.HASHED_USER_ID
        provider.redirect_uris = [
            RedirectURI(RedirectURIMatchingMode.STRICT, uri)
            for uri in redirect_uris
        ]
        provider.save()
        provider.property_mappings.set(mappings)
        print(f"{'created' if created else 'updated'} OIDC provider {provider_name}")
        return provider


    def ensure_application(slug, name, launch_url, provider):
        app = Application.objects.filter(slug=slug).first()
        created = app is None
        if app is None:
            app = Application(slug=slug)
        app.name = name
        app.provider = provider
        app.open_in_new_tab = True
        app.meta_launch_url = launch_url
        app.policy_engine_mode = PolicyEngineMode.MODE_ANY
        app.save()
        print(f"{'created' if created else 'updated'} application {slug}")
        return app


    def ensure_binding(app, group_name, order):
        group = ensure_group(group_name)
        binding = PolicyBinding.objects.filter(target=app, group=group).first()
        created = binding is None
        if binding is None:
            binding = PolicyBinding(target=app, group=group)
        binding.order = order
        binding.enabled = True
        binding.negate = False
        binding.timeout = 30
        binding.failure_result = False
        binding.save()
        print(f"{'created' if created else 'updated'} application binding for group {group_name}")


    def remove_stale_oidc_providers(desired_provider_names):
        stale_providers = list(
            OAuth2Provider.objects.filter(name__startswith="fleet-", name__endswith="-oidc")
            .exclude(name__in=desired_provider_names)
        )
        for provider in stale_providers:
            application = Application.objects.filter(provider=provider).first()
            if application is not None:
                print(f"deleted OIDC application {application.slug}")
                application.delete()
            print(f"deleted OIDC provider {provider.name}")
            provider.delete()


    with transaction.atomic():
        authorization_flow = ensure_flow(
            "default-provider-authorization-implicit-consent",
            "authorization",
            "Authorize Application",
            "Redirecting to %(app)s",
            "require_authenticated",
        )
        invalidation_flow = ensure_flow(
            "default-provider-invalidation-flow",
            "invalidation",
            "Logged out of application",
            "You've logged out of %(app)s.",
            "none",
        )
        mappings = oidc_scope_mappings()

        for group in declared_groups:
            ensure_group(group)
        for group in declared_admin_groups:
            ensure_group(group)
        ensure_bootstrap_admin_groups()

        desired_provider_names = []
        for app in declared_applications:
            slug = app["slug"]
            name = app["name"]
            mode = app["mode"]
            if mode == "forward-auth":
                print(
                    f"forwardAuth proxy provisioning is disabled for {name} ({slug}); "
                    "remove or replace this declaration with native app SSO"
                )
                continue
            if mode == "native-oidc":
                provider = ensure_oidc_provider(app, authorization_flow, invalidation_flow, mappings)
                oidc = app.get("oidc") or {}
                launch_url = oidc.get("launchUrl") or (
                    f"https://{app['hosts'][0]}" if app.get("hosts") else ""
                )
                application = ensure_application(slug, name, launch_url, provider)
                desired_provider_names.append(provider.name)
                binding_groups = list(dict.fromkeys(declared_admin_groups + app.get("groups", [])))
                for order, group in enumerate(binding_groups):
                    ensure_binding(application, group, order)
                continue
            print(
                f"declared native Authentik application {name} ({slug}, mode={mode}); "
                "app-specific configuration is handled outside OIDC provisioning"
            )
        remove_stale_proxy_providers(desired_provider_names)
        remove_stale_oidc_providers(desired_provider_names)
  '';

  provisioningScript = pkgs.writeShellScript "fleet-authentik-provision" ''
    set -euo pipefail

    wait_for_authentik() {
      for attempt in $(seq 1 120); do
        if curl -fsS "http://${cfg.listenAddress}:${toString cfg.httpPort}/-/health/ready/" >/dev/null; then
          return 0
        fi
        sleep 1
      done

      echo "authentik API did not become ready" >&2
      exit 1
    }

    wait_for_authentik
    ${lib.getExe pkgs.python3} -c 'import pathlib, textwrap; print(textwrap.dedent(pathlib.Path("${provisioningPython}").read_text()), end="")' | ${authentikWrapper} shell
  '';
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.authentik = {
    enable = mkEnableOption "Authentik identity provider on gateway-vm";

    package = mkOption {
      type = types.package;
      default = pkgs.authentik;
      defaultText = literalExpression "pkgs.authentik";
      description = "Authentik package to run.";
    };

    domain = mkOption {
      type = types.str;
      default = "auth.jax22.com";
      description = "Canonical public Authentik hostname.";
    };

    aliases = mkOption {
      type = types.listOf types.str;
      default = [ "auth.h" ];
      description = "Unprotected LAN Authentik aliases.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/srv/appsdata/authentik";
      description = "Authoritative Authentik state root.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address for Authentik HTTP and metrics listeners.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 9000;
      description = "Authentik HTTP listener port.";
    };

    metricsPort = mkOption {
      type = types.port;
      default = 9300;
      description = "Authentik metrics listener port.";
    };

    secretKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Runtime file containing AUTHENTIK_SECRET_KEY.";
    };

    groups = mkOption {
      type = types.listOf types.str;
      default = [
        "fleet-admins"
        "media-users"
        "monitoring-users"
        "productivity-users"
      ];
      description = "Role groups that the provisioning unit ensures exist.";
    };

    adminGroups = mkOption {
      type = types.listOf types.str;
      default = [ "fleet-admins" ];
      description = "Role groups that can reach every managed Authentik application.";
    };

    applications = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            slug = mkOption { type = types.str; };
            name = mkOption { type = types.str; };
            mode = mkOption {
              type = types.enum [
                "forward-auth"
                "native-header"
                "native-oidc"
              ];
            };
            groups = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            hosts = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            oidc = {
              clientId = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "OIDC client ID. Defaults to the application slug.";
              };

              clientSecretFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Runtime file containing the OIDC client secret.";
              };

              clientType = mkOption {
                type = types.enum [
                  "confidential"
                  "public"
                ];
                default = "confidential";
                description = "OAuth2 client type.";
              };

              includeClaimsInIdToken = mkOption {
                type = types.bool;
                default = true;
                description = "Include scope claims in the ID token.";
              };

              launchUrl = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Launch URL shown in Authentik for this application.";
              };

              redirectUris = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Strict redirect URIs allowed for this OIDC client.";
              };

              subMode = mkOption {
                type = types.enum [
                  "hashed_user_id"
                  "user_id"
                  "user_uuid"
                  "user_username"
                  "user_email"
                  "user_upn"
                ];
                default = "hashed_user_id";
                description = "Authentik subject identifier mode.";
              };
            };
          };
        }
      );
      default = [ ];
      description = "Declared Authentik application inventory used by the provisioning unit.";
    };

    bootstrap = {
      email = mkOption {
        type = types.str;
        default = "admin@jax22.com";
        description = "Bootstrap admin email.";
      };

      username = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional bootstrap admin username.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the initial bootstrap admin password.";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the bootstrap API token.";
      };
    };

    postgresql = {
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the Authentik PostgreSQL role password.";
      };
    };

    provisioning = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the idempotent Authentik provisioning unit after Authentik starts.";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing an Authentik API token for fleet provisioning.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretKeyFile != null;
        message = "fleet.gateway.authentik.secretKeyFile must be set.";
      }
      {
        assertion = cfg.postgresql.passwordFile != null;
        message = "fleet.gateway.authentik.postgresql.passwordFile must be set.";
      }
      {
        assertion = !cfg.provisioning.enable || cfg.provisioning.tokenFile != null;
        message = "fleet.gateway.authentik.provisioning.tokenFile must be set when provisioning is enabled.";
      }
    ];

    users.groups.authentik = { };
    users.users.authentik = {
      description = "Authentik service user";
      group = "authentik";
      home = cfg.stateDir;
      isSystemUser = true;
    };

    services.postgresql = {
      enable = true;
      dataDir = postgresqlDataDir;
      ensureDatabases = [ "authentik" ];
      ensureUsers = [
        {
          name = "authentik";
          ensureDBOwnership = true;
        }
      ];
      settings.max_connections = 300;
      authentication = mkAfter ''
        host authentik authentik 127.0.0.1/32 scram-sha-256
      '';
    };

    services.redis.servers.authentik = {
      enable = true;
      appendOnly = true;
      bind = "127.0.0.1";
      openFirewall = false;
      port = 6379;
      settings.dir = mkForce redisDataDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 root authentik - -"
      "d ${cfg.stateDir}/certs 0750 authentik authentik - -"
      "d ${cfg.stateDir}/media 0750 authentik authentik - -"
      "d ${cfg.stateDir}/postgresql 0750 postgres postgres - -"
      "d ${postgresqlDataDir} 0750 postgres postgres - -"
      "d ${redisDataDir} 0750 redis-authentik redis-authentik - -"
    ];

    systemd.services.authentik-postgresql-password = {
      description = "Set Authentik PostgreSQL role password";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
      };
      path = [
        config.services.postgresql.package
        pkgs.coreutils
        pkgs.gnused
      ];
      script = ''
        set -euo pipefail

        password="$(<${secretFile cfg.postgresql.passwordFile})"
        escaped="$(${lib.getExe pkgs.python3} -c 'import sys; print(sys.stdin.read().replace(chr(39), chr(39) * 2), end="")' <<<"$password")"
        printf "ALTER ROLE authentik WITH PASSWORD '%s';\n" "$escaped" | psql -d postgres
      '';
    };

    systemd.services.postgresql.serviceConfig = {
      ReadWritePaths = mkForce [ "${cfg.stateDir}/postgresql" ];
      SupplementaryGroups = [ "authentik" ];
    };
    systemd.services.redis-authentik.serviceConfig = {
      ReadWritePaths = [ redisDataDir ];
      SupplementaryGroups = [ "authentik" ];
    };

    systemd.services.authentik-server = {
      description = "Authentik server";
      after = [
        "authentik-postgresql-password.service"
        "network-online.target"
        "postgresql.service"
        "redis-authentik.service"
      ];
      requires = [
        "authentik-postgresql-password.service"
        "postgresql.service"
        "redis-authentik.service"
      ];
      wants = [ "network-online.target" ];
      environment = authentikEnvironment;
      serviceConfig = {
        ExecStart = "${authentikWrapper} server";
        Group = "authentik";
        Restart = "on-failure";
        StateDirectory = "authentik";
        Type = "simple";
        User = "authentik";
        WorkingDirectory = cfg.stateDir;
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.authentik-worker = {
      description = "Authentik worker";
      after = [
        "authentik-postgresql-password.service"
        "authentik-server.service"
        "network-online.target"
        "postgresql.service"
        "redis-authentik.service"
      ];
      requires = [
        "authentik-postgresql-password.service"
        "postgresql.service"
        "redis-authentik.service"
      ];
      wants = [
        "authentik-server.service"
        "network-online.target"
      ];
      environment = authentikEnvironment;
      serviceConfig = {
        ExecStart = "${authentikWrapper} worker";
        Group = "authentik";
        Restart = "on-failure";
        StateDirectory = "authentik";
        Type = "simple";
        User = "authentik";
        WorkingDirectory = cfg.stateDir;
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.authentik-provision = mkIf cfg.provisioning.enable {
      description = "Provision fleet Authentik groups and applications";
      after = [
        "authentik-server.service"
        "authentik-worker.service"
      ];
      before = [ "traefik.service" ];
      requiredBy = [ "traefik.service" ];
      requires = [
        "authentik-server.service"
        "authentik-worker.service"
      ];
      wants = [ "authentik-worker.service" ];
      serviceConfig = {
        ExecStart = provisioningScript;
        Group = "authentik";
        Type = "oneshot";
        User = "authentik";
        WorkingDirectory = cfg.stateDir;
      };
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      wantedBy = [
        "authentik-worker.service"
        "multi-user.target"
      ];
    };
  };
}
