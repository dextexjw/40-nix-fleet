import json
import os

from django.db import transaction

from authentik.core.models import Application, Group, PropertyMapping, User
from authentik.crypto.models import CertificateKeyPair
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

with open("@groupProvisioningJson@", "r", encoding="utf-8") as groups_file:
    declared_groups = json.load(groups_file)["groups"]

with open("@applicationProvisioningJson@", "r", encoding="utf-8") as applications_file:
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


def oidc_signing_key(oidc, slug):
    key_name = oidc.get("signingKeyName") or "authentik Self-signed Certificate"
    key = CertificateKeyPair.objects.filter(name=key_name).first()
    if key is None:
        raise ValueError(f"native OIDC application {slug} signing key {key_name!r} was not found")
    return key


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
    provider.signing_key = oidc_signing_key(oidc, slug)
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
