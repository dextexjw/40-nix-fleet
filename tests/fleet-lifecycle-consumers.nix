{
  consumers,
  pkgs,
}:

let
  expectedGatewaySurfaces = [
    "authentication"
    "dns"
    "firewall"
    "homepage"
    "route"
    "smoke"
    "tls"
  ];
  applicableSurfacesRendered = builtins.all (
    host: builtins.all (surface: host.rendered.${surface}) host.consumerSurfaces
  ) (builtins.attrValues consumers);
  applicableSurfacesHaveEvidence = builtins.all (
    host: builtins.all (surface: host.evidence.${surface} != null) host.consumerSurfaces
  ) (builtins.attrValues consumers);
in
assert consumers.gateway-vm.consumerSurfaces == expectedGatewaySurfaces;
assert consumers.gateway2-vm.consumerSurfaces == expectedGatewaySurfaces;
assert builtins.elem "monitoring" consumers.monitoring-vm.consumerSurfaces;
assert applicableSurfacesRendered;
assert applicableSurfacesHaveEvidence;
pkgs.runCommand "fleet-lifecycle-consumers-check" { } ''
  touch "$out"
''
