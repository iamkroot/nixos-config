{
  lib,
  config,
  pii,
  myUtils,
  ...
}:
let
  baseDN = myUtils.domainToBaseDN config.infra.domain;
in
{

  vaultix.secrets =
    lib.genAttrs
      [
        "authelia-jwt"
        "authelia-ldap"
        "authelia-session"
        "authelia-storage"
        "authelia-oidc-cert"
        "authelia-oidc-hmac"
      ]
      (name: {
        file = pii.secrets.${name};
        owner = "authelia-main";
        group = "authelia-main";
      });

  systemd.services."authelia-main" = {
    serviceConfig = {
      LoadCredential = [
        "jwt_secret:${config.vaultix.secrets.authelia-jwt.path}"
        "session_secret:${config.vaultix.secrets.authelia-session.path}"
        "storage_secret:${config.vaultix.secrets.authelia-storage.path}"
        "ldap_password:${config.vaultix.secrets.authelia-ldap.path}"
        "oidc_cert:${config.vaultix.secrets.authelia-oidc-cert.path}"
        "oidc_hmac:${config.vaultix.secrets.authelia-oidc-hmac.path}"
      ];
    };
  };

  services.authelia.instances."main" = {
    enable = true;

    secrets = {
      jwtSecretFile = "/run/credentials/authelia-main.service/jwt_secret";
      sessionSecretFile = "/run/credentials/authelia-main.service/session_secret";
      storageEncryptionKeyFile = "/run/credentials/authelia-main.service/storage_secret";
      oidcIssuerPrivateKeyFile = "/run/credentials/authelia-main.service/oidc_cert";
      oidcHmacSecretFile = "/run/credentials/authelia-main.service/oidc_hmac";
    };

    environmentVariables = {
      AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = "/run/credentials/authelia-main.service/ldap_password";
    };

    settings = {
      theme = "dark";

      server.address = "tcp://127.0.0.1:${toString config.infra.services.ports.authelia}";

      session = {
        cookies = [
          {
            domain = config.infra.domain;
            authelia_url = "https://${config.infra.services.hostnames.auth}";
          }
        ];
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      notifier = {
        filesystem = {
          filename = "/var/lib/authelia-main/emails.txt";
        };
      };

      authentication_backend.ldap = {
        implementation = "lldap";

        address = "ldap://127.0.0.1:${toString config.infra.services.ports.lldap_ldap}";
        base_dn = baseDN;
        user = "uid=authelia_svc,ou=people,${baseDN}";
      };

      access_control = {
        default_policy = "deny";
        rules = [
          # Bypass auth for Authelia itself
          {
            domain = config.infra.services.hostnames.auth;
            policy = "bypass";
          }
          # TODO: Require 2FA for everything else by default
          {
            domain = "*.${config.infra.domain}";
            policy = "one_factor";
          }
        ];
      };

      identity_providers.oidc.clients = [
        {
          client_id = pii.secrets.authelia-jellyfin-client-id;
          client_secret = pii.secrets.authelia-jellyfin-client-secret;
          client_name = "Jellyfin";
          public = false;
          token_endpoint_auth_method = "client_secret_post";
          authorization_policy = "one_factor";
          redirect_uris = [
            "https://${config.infra.services.hostnames.jellyfin}/sso/OID/redirect/authelia"
          ];
        }
      ];
    };
  };

  services.caddy.virtualHosts."${config.infra.services.hostnames.auth}" = {
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString config.infra.services.ports.authelia}
    '';
    logFormat = ''
      output file /var/log/caddy/access-${config.infra.services.hostnames.auth}.log {
        roll_size 50mb
        roll_keep 5
      }
    '';
  };
}
