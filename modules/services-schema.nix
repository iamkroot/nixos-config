{ lib, ... }:
let
  t = lib.types;
in
{
  options.myServices = lib.mkOption {
    description = "Homelab services configuration schema";
    type = t.attrsOf (
      t.submodule (
        { name, config, ... }: {
          options = {
            enable = lib.mkOption {
              type = t.bool;
              default = true;
              description = "If true, service is included in the host's configuration and DNS generation.";
            };
            port = lib.mkOption {
              type = t.port;
              default = 0;
              description = "Primary port, exposed to other modules via config.infra.services.ports.";
            };
            host = lib.mkOption {
              type = t.enum (builtins.attrNames (import ../secrets/pii.nix).hosts);
              description = "Target machine in pii.hosts. Used by flake.nix to assign the module and DNS scripts for IPs.";
            };
            module = lib.mkOption {
              type = t.nullOr t.str;
              default = name;
              description = "Basename of the file in modules/services/ to import when this service is active. Set to null to disable auto-import or if imported from another module.";
            };
            subdomain = lib.mkOption {
              type = t.nullOr t.str;
              default = name;
              description = "Subdomain used for Caddy virtual hosts and Porkbun/dnsmasq DNS records.";
            };
            dns = lib.mkOption {
              type = t.bool;
              default = true;
              description = "If true, includes this service in DNS sync scripts (porkbun/router).";
            };
            extraPorts = lib.mkOption {
              type = t.attrsOf t.port;
              default = { };
              description = "Additional ports to expose in config.infra.services.ports.";
            };
            catalog = {
              enable = lib.mkOption {
                type = t.bool;
                default = true;
                description = "If true, adds the service to the Account Center (dashboard) catalog.";
              };
              roles = lib.mkOption {
                type = t.attrsOf t.str;
                default = { };
                description = "Roles required to view this service in the Account Center catalog.";
              };
            };
          };
        }
      )
    );
  };
  config.myServices = import ../secrets/services.nix;
}
