# declare the schemas here
# actual values can be overriden in secrets/ports.nix
{
  config,
  lib,
  pii,
  myUtils,
  ...
}:
{
  options.infra.services.ports = {
    atuin = myUtils.mkPortOption 8888 "Port for the Atuin sync server";

    caddy = myUtils.mkPortOption 443 "HTTPS port for Caddy reverse proxy";

    lldap_ldap = myUtils.mkPortOption 3890 "LDAP port for LLDAP";
    lldap_http = myUtils.mkPortOption 17170 "HTTP port for LLDAP";

    authelia = myUtils.mkPortOption 9091 "Port for Authelia service";

    aria2 = myUtils.mkPortOption 6800 "Port for aria2 RPC server";
    ariang = myUtils.mkPortOption 0 "Fake port";

    whoami = myUtils.mkPortOption 8080 "Port for aria2 RPC server";

    adguard = myUtils.mkPortOption 3000 "Port for adguard webui";

    redlib = myUtils.mkPortOption 18080 "Port for redlib webui";
    anubis_redlib = myUtils.mkPortOption 38080 "Port for anubis middleware for redlib";

    et = myUtils.mkPortOption 2022 "Port for eternal terminal server";

    yopass = myUtils.mkPortOption 1337 "Port for yopass";

    httpserver = myUtils.mkPortOption 12345 "Port for httpserver";

    shoko = myUtils.mkPortOption 8111 "Port for shokoserver";

    jellyfin = myUtils.mkPortOption 8096 "Port for jellyfin";
    seerr = myUtils.mkPortOption 5055 "Port for seerr";

    vaultwarden = myUtils.mkPortOption 8222 "Port for vaultwarden Rocket";

    immich = myUtils.mkPortOption 2283 "Port for immich";

    "account-center" = myUtils.mkPortOption 8085 "Port for account-center";

    icons = myUtils.mkPortOption 0 "Fake port";

    radarr = myUtils.mkPortOption 7878 "Port for radarr";
    sonarr = myUtils.mkPortOption 8989 "Port for sonarr";
    prowlarr = myUtils.mkPortOption 9696 "Port for prowlarr";
    decypharr = myUtils.mkPortOption 8282 "Port for decypharr";
    profilarr = myUtils.mkPortOption 6868 "Port for profilarr";
    revaulter = myUtils.mkPortOption 28081 "Port for revaulter";
  };
  options.infra.domain = lib.mkOption {
    type = lib.types.str;
    description = "Base domain name";
  };
  options.infra.services.hostnames = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Mapping of my homelab services to their hostnames.";
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

  config.infra.services.catalog = lib.mapAttrs (svc: host: {
    enable = lib.mkDefault (config.services.caddy.virtualHosts ? "${host}");
    name = lib.mkDefault (lib.toUpper (lib.substring 0 1 svc) + lib.substring 1 (-1) svc);
    url = lib.mkDefault "https://${host}";
    icon = lib.mkDefault "https://${config.infra.services.hostnames.icons}/${svc}.svg";
  }) config.infra.services.hostnames;
}
