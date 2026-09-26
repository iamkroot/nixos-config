{
  config,
  lib,
  pii,
  services,
  hostKey,
  myUtils,
  ...
}:
{
  options.infra.hostKey = lib.mkOption {
    type = lib.types.str;
    description = "Key into pii.hosts for this machine.";
  };

  options.infra.domain = lib.mkOption {
    type = lib.types.str;
    description = "Base domain name";
  };

  options.infra.services.ports = lib.mkOption {
    type = lib.types.attrsOf lib.types.port;
    default = { };
    description = "Service ports. Auto-populated from services.nix.";
  };

  options.infra.services.hostnames = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Mapping of my services to their hostnames.";
  };

  options.infra.services.catalog = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Include in Account Center catalog" // {
            default = true;
          };
          name = lib.mkOption { type = lib.types.str; };
          url = lib.mkOption { type = lib.types.str; };
          icon = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          roles = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {
              lldap_admin = "system_administrator";
            };
          };
        };
      }
    );
    default = { };
    description = "Account Center catalog entries.";
  };

  options.infra.dns = {
    adguard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether AdGuard Home DNS integration is active.";
      };
      location = lib.mkOption {
        type = lib.types.str;
        default = "router2";
        description = "Location of AdGuard Home: 'homelab1' or 'local' to run locally on homelab1, or a host/appliance key in pii (e.g. 'router2') to proxy and sync certs.";
      };
      dotSubdomain = lib.mkOption {
        type = lib.types.str;
        default = "dns";
        description = "Subdomain used for DNS-over-TLS (DoT).";
      };
      syncCerts = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to automatically sync renewed wildcard TLS certs via ACME postRun.";
      };
    };
  };

  config.infra.hostKey = hostKey;
  config.infra.domain = pii.primaryDomain;

  config.infra.services.ports = lib.mkMerge (
    [ (lib.mapAttrs (_: s: lib.mkDefault (s.port or 0)) services) ]
    ++ (lib.mapAttrsToList (
      _: s: lib.mapAttrs (_: port: lib.mkDefault port) (s.extraPorts or { })
    ) services)
  );

  config.infra.services.hostnames = lib.mapAttrs (
    name: s: if s.subdomain != null then "${s.subdomain}.${config.infra.domain}" else null
  ) services;

  config.infra.services.catalog = lib.mapAttrs (
    name: s:
    let
      hostname = if s.subdomain != null then "${s.subdomain}.${config.infra.domain}" else null;
    in
    {
      enable = lib.mkDefault (
        (s.catalog.enable or true)
        && hostname != null
        && (config.services.caddy.virtualHosts ? "${hostname}")
      );
      name = lib.mkDefault (lib.toUpper (lib.substring 0 1 name) + lib.substring 1 (-1) name);
      url = lib.mkDefault (if hostname != null then "https://${hostname}" else "");
      icon = lib.mkDefault "https://${config.infra.services.hostnames.icons}/${name}.svg";
      roles = lib.mkDefault (s.catalog.roles or { lldap_admin = "system_administrator"; });
    }
  ) services;

  config.services.caddy.virtualHosts = lib.mkMerge (
    lib.mapAttrsToList (
      name: s:
      let
        oldHost = "${s.subdomain}.${pii.oldDomain}";
        newHost = "${s.subdomain}.${config.infra.domain}";
      in
      lib.mkIf (s.host == hostKey && s.subdomain != null) {
        "${oldHost}" = {
          extraConfig = "redir https://${newHost}{uri}";
        };
      }
    ) services
  );
}
