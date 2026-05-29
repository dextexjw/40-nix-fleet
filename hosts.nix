# ============================================================================
# FLEET HOST DEFINITIONS
# Single source of truth for all host information
# ============================================================================

{
  gateway-vm = {
    arch = "x86_64-linux";
    domain = "home.arpa";
    fqdn = "gateway.home.arpa";
    ip = "10.2.20.112";
    gateway = "10.2.20.1";
    nameservers = [
      "10.2.20.1"
    ];
    user = "smoke";
    tags = [
      "gateway"
    ];
    timezone = "America/New_York";
    vm = {
      cores = 2;
      disk = "/dev/sda";
      id = "112";
      name = "gateway-vm";
      ramGB = 3;
    };
  };

  media-vm = {
    arch = "x86_64-linux";
    domain = "home.arpa";
    fqdn = "media.home.arpa";
    ip = "10.2.20.113";
    gateway = "10.2.20.1";
    nameservers = [
      "10.2.20.1"
    ];
    user = "smoke";
    tags = [
      "media"
    ];
    timezone = "America/New_York";
    vm = {
      cores = 4;
      disk = "/dev/sda";
      id = "113";
      name = "media-vm";
      ramGB = 8;
    };
  };

  productivity-vm = {
    arch = "x86_64-linux";
    domain = "home.arpa";
    fqdn = "productivity.home.arpa";
    ip = "10.2.20.114";
    gateway = "10.2.20.1";
    nameservers = [
      "10.2.20.1"
      "9.9.9.9"
    ];
    user = "smoke";
    tags = [
      "productivity"
    ];
    timezone = "America/New_York";
    vm = {
      cores = 4;
      disk = "/dev/sda";
      id = "114";
      name = "productivity-vm";
      ramGB = 8;
    };
  };

  security-vm = {
    arch = "x86_64-linux";
    domain = "home.arpa";
    fqdn = "security.home.arpa";
    ip = "10.2.20.115";
    gateway = "10.2.20.1";
    nameservers = [
      "10.2.20.1"
      "9.9.9.9"
    ];
    user = "smoke";
    tags = [
      "security"
    ];
    timezone = "America/New_York";
    vm = {
      cores = 2;
      disk = "/dev/sda";
      id = "115";
      name = "security-vm";
      ramGB = 4;
    };
  };
}
