{
  hosts,
  serviceDomain,
  serviceDomains ? [ serviceDomain ],
  ...
}:

import ../../modules/monitoring/catalog.nix {
  host = hosts.monitoring-vm;
  inherit serviceDomain serviceDomains;
}
