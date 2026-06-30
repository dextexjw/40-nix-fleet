{
  hosts,
  serviceDomain,
  serviceDomains ? [ serviceDomain ],
  ...
}:

import ../../modules/testbed/catalog.nix {
  host = hosts.testbed-vm;
  inherit serviceDomain serviceDomains;
}
