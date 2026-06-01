{ hosts, serviceDomain, ... }:

import ../../modules/productivity/catalog.nix {
  host = hosts.productivity-vm;
  inherit serviceDomain;
}
