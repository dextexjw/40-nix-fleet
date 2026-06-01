{ hosts, serviceDomain, ... }:

import ../../modules/media/catalog.nix {
  host = hosts.media-vm;
  inherit serviceDomain;
}
