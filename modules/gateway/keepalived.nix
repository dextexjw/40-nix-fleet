{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.keepalived;
  peerAddresses = filter (address: address != cfg.hostAddress) cfg.peerAddresses;
  firewallRuleFor =
    action: peerAddress:
    "iptables ${action} nixos-fw -i ${cfg.interface} -s ${peerAddress} -p vrrp -m comment --comment fleet.gateway.keepalived -j ACCEPT";
  healthScript = pkgs.writeShellScript "gateway-vip-health-check" ''
    set -eu

    ${pkgs.systemd}/bin/systemctl is-active --quiet systemd-networkd.service
    ${pkgs.systemd}/bin/systemctl is-active --quiet traefik.service
    ${pkgs.systemd}/bin/systemctl is-active --quiet technitium-dns-server.service
    ${pkgs.systemd}/bin/systemctl is-active --quiet homepage-dashboard.service

    ${pkgs.iproute2}/bin/ss -ltn '( sport = :80 )' | ${pkgs.gnugrep}/bin/grep -q ':80'
    ${pkgs.iproute2}/bin/ss -ltn '( sport = :443 )' | ${pkgs.gnugrep}/bin/grep -q ':443'
    ${pkgs.iproute2}/bin/ss -lun '( sport = :53 )' | ${pkgs.gnugrep}/bin/grep -q ':53'
  '';
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.keepalived = {
    enable = mkEnableOption "Gateway VRRP failover VIP";

    hostAddress = mkOption {
      type = types.str;
      description = "This Gateway node's static LAN address used as the VRRP unicast source.";
      example = "10.2.20.112";
    };

    interface = mkOption {
      type = types.str;
      default = "ens18";
      description = "LAN interface that owns the Gateway VRRP VIP.";
    };

    peerAddresses = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Gateway peer addresses used for unicast VRRP advertisements.";
      example = [
        "10.2.20.112"
        "10.2.20.122"
      ];
    };

    priority = mkOption {
      type = types.ints.between 1 255;
      default = 100;
      description = "VRRP election priority. The highest healthy node owns the VIP.";
    };

    vip = mkOption {
      type = types.str;
      description = "Shared Gateway virtual IP address.";
      example = "10.2.20.102";
    };

    virtualRouterId = mkOption {
      type = types.ints.between 1 255;
      default = 102;
      description = "Unique VRRP router ID for the Gateway VIP on the LAN.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hostAddress != cfg.vip;
        message = "fleet.gateway.keepalived.hostAddress must be a real member IP, not the VIP.";
      }
      {
        assertion = peerAddresses != [ ];
        message = "fleet.gateway.keepalived.peerAddresses must include at least one peer other than this host.";
      }
    ];

    services.keepalived = {
      enable = true;
      enableScriptSecurity = true;
      openFirewall = false;
      vrrpScripts.gateway_services = {
        script = "${healthScript}";
        fall = 2;
        interval = 2;
        rise = 3;
        timeout = 2;
        user = "root";
        weight = -60;
      };
      vrrpInstances.gateway_vip = {
        interface = cfg.interface;
        priority = cfg.priority;
        state = "BACKUP";
        trackInterfaces = [ cfg.interface ];
        trackScripts = [ "gateway_services" ];
        unicastPeers = peerAddresses;
        unicastSrcIp = cfg.hostAddress;
        virtualIps = [
          {
            addr = "${cfg.vip}/24";
            dev = cfg.interface;
            scope = "global";
          }
        ];
        virtualRouterId = cfg.virtualRouterId;
      };
    };

    networking.firewall = {
      extraCommands = concatMapStringsSep "\n" (
        peerAddress:
        let
          rule = firewallRuleFor "-A" peerAddress;
          checkRule = firewallRuleFor "-C" peerAddress;
        in
        "${checkRule} 2>/dev/null || ${rule}"
      ) peerAddresses;
      extraStopCommands = concatMapStringsSep "\n" (
        peerAddress: "${firewallRuleFor "-D" peerAddress} 2>/dev/null || true"
      ) peerAddresses;
    };

    environment.etc."fleet/gateway-ha.json".text = builtins.toJSON {
      inherit (cfg)
        hostAddress
        interface
        peerAddresses
        priority
        vip
        virtualRouterId
        ;
      healthCheck = "systemd-networkd, Traefik, Technitium, Homepage, and listeners tcp/80 tcp/443 udp/53";
      role = if cfg.priority >= 150 then "preferred-primary" else "standby";
    };
  };
}
