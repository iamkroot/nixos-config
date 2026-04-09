{
  lib,
  config,
  pkgs,
  pii,
  myUtils,
  ...
}:
let
  baseDN = myUtils.domainToBaseDN config.infra.domain;
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

  systemd.services.lldap = {
    serviceConfig = {
      # This 'pushes' the secret into the service's private space
      LoadCredential = [
        "lldap_jwt:${config.vaultix.secrets.lldap-jwt.path}"
        "lldap_admin_pass:${config.vaultix.secrets.lldap-admin-pass.path}"
      ];
    };
  };

  services.lldap = {
    enable = true;
    settings = {
      ldap_user_pass_file = "/run/credentials/lldap.service/lldap_admin_pass";
      jwt_secret_file = "/run/credentials/lldap.service/lldap_jwt";
      force_ldap_user_pass_reset = "always"; # override webui
      http_url = "https://${config.infra.services.hostnames.ldap}";
      ldap_base_dn = baseDN;
      ldap_host = "127.0.0.1";
      ldap_port = config.infra.services.ports.lldap_ldap;
      http_host = "127.0.0.1";
      http_port = config.infra.services.ports.lldap_http;
    };
  };

  services.caddy.virtualHosts."${config.infra.services.hostnames.ldap}" = {
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString config.infra.services.ports.lldap_http}
    '';
    logFormat = ''
      output file /var/log/caddy/access-${config.infra.services.hostnames.ldap}.log {
        roll_size 50mb
        roll_keep 5
      }
    '';
  };
}
