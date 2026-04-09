# declare the schemas here
# actual values can be overriden in secrets/ports.nix
{
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
}
