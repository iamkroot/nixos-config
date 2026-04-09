{
  lib,
  config,
  pkgs,
  pii,
  myUtils,
  ...
}:
let
  domainToBaseDN =
    domain: lib.concatStringsSep "," (map (part: "dc=${part}") (lib.splitString "." domain));
  baseDN = domainToBaseDN config.infra.domain;
in
{
  vaultix.secrets."lldap-admin-pass" = {
    file = pii.secrets.lldap-admin-pass;
    owner = "lldap";
    group = "lldap";
  };
  vaultix.secrets."lldap-jwt" = {
    file = pii.secrets.lldap-jwt;
    owner = "lldap";
    group = "lldap";
  };

  services.lldap = {
    enable = true;
    settings = {
      ldap_user_pass_file = config.vaultix.secrets.lldap-admin-pass.path;
      jwt_secret_file = config.vaultix.secrets.lldap-jwt.path;
      force_ldap_user_pass_reset = "always"; # override webui
      http_url = "https://${config.infra.services.hostnames.ldap}";
      ldap_base_dn = baseDN;
      ldap_host = "127.0.0.1";
      ldap_port = config.infra.services.ports.lldap_ldap;
      http_host = "127.0.0.1";
      http_port = config.infra.services.ports.lldap_http;
    };
  };
}
