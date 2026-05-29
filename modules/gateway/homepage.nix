{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.homepage;
  settingsFormat = pkgs.formats.yaml { };

  allowedHosts = concatStringsSep "," (
    unique (
      [
        cfg.host
        "${cfg.host}:80"
        "localhost:${toString cfg.listenPort}"
        "127.0.0.1:${toString cfg.listenPort}"
      ]
      ++ optionals (cfg.directAddress != null) [
        cfg.directAddress
        "${cfg.directAddress}:${toString cfg.listenPort}"
      ]
    )
  );

  mkHomepageService = service: {
    ${service.name} = {
      inherit (service) description href;
    } // optionalAttrs (service.icon != null) {
      inherit (service) icon;
    } // optionalAttrs (service.siteMonitor != null) {
      inherit (service) siteMonitor;
    };
  };

  mkHomepageGroup = group: {
    ${group.name} = map mkHomepageService group.services;
  };
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.homepage = {
    enable = mkEnableOption "Homepage dashboard for gateway-vm services";

    bookmarks = mkOption {
      inherit (settingsFormat) type;
      default = [ ];
      description = "Homepage bookmarks configuration.";
      example = [
        {
          Links = [
            {
              GitHub = [
                {
                  href = "https://github.com/";
                  icon = "github.png";
                }
              ];
            }
          ];
        }
      ];
    };

    directAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Direct LAN address used to access Homepage without Traefik.";
      example = "10.2.20.112";
    };

    customCSS = mkOption {
      type = types.lines;
      default = "";
      description = "Custom CSS for Homepage.";
    };

    host = mkOption {
      type = types.str;
      default = "homepage.h";
      description = "Hostname used for Homepage through Traefik.";
      example = "homepage.h";
    };

    linkTarget = mkOption {
      type = types.str;
      default = "_self";
      description = "Browser target used when opening Homepage service card links.";
      example = "_blank";
    };

    layout = mkOption {
      inherit (settingsFormat) type;
      default = { };
      description = "Homepage layout settings keyed by service or bookmark group name.";
      example = [
        {
          Gateway = {
            columns = 4;
            style = "row";
          };
        }
      ];
    };

    listenPort = mkOption {
      type = types.port;
      default = 8082;
      description = "Port for Homepage to listen on.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the Homepage listen port on the host firewall.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.homepage-dashboard;
      defaultText = literalExpression "pkgs.homepage-dashboard";
      description = "Homepage package to run on gateway-vm.";
    };

    serviceGroups = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Homepage service group name.";
              example = "Gateway";
            };

            services = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    name = mkOption {
                      type = types.str;
                      description = "Homepage service card name.";
                      example = "Traefik";
                    };

                    description = mkOption {
                      type = types.str;
                      default = "";
                      description = "Homepage service card description.";
                    };

                    href = mkOption {
                      type = types.str;
                      description = "URL opened by the Homepage service card.";
                      example = "http://traefik.h/dashboard/";
                    };

                    icon = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Optional Homepage icon reference.";
                      example = "traefik.png";
                    };

                    siteMonitor = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Optional URL Homepage should monitor for this service card.";
                      example = "http://traefik.h/dashboard/";
                    };
                  };
                }
              );
              default = [ ];
              description = "Homepage service cards in this group.";
            };
          };
        }
      );
      default = [ ];
      description = "Ordered Homepage service groups.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    services.homepage-dashboard = {
      allowedHosts = allowedHosts;
      bookmarks = cfg.bookmarks;
      customCSS = cfg.customCSS;
      enable = true;
      listenPort = cfg.listenPort;
      openFirewall = cfg.openFirewall;
      package = cfg.package;
      services = map mkHomepageGroup cfg.serviceGroups;
      settings = {
        description = "Declarative service directory for gateway-vm.";
        disableUpdateCheck = true;
        layout = cfg.layout;
        target = cfg.linkTarget;
        title = "homepage.h";
      };
    };

    systemd.services.homepage-dashboard = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
  };
}
