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
  imports = [
    (myUtils.mkCaddyModule "auth" { portKey = "authelia"; })
    # Inline anonymous module to avoid wrapping the configs later
    ({ lib, ... }: {
      options.myAuthelia = {
        accessRules = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
          description = "Authelia access control rules, ususally collected from service modules via mkAutheliaAccess.";
        };
        oidcClients = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
          description = "Authelia OIDC client registrations, ususally collected from service modules via mkAutheliaOIDC.";
        };
      };
    })
  ];

  vaultix.secrets = builtins.listToAttrs (
    map
      (name: {
        name = "authelia-${name}";
        value = {
          file = pii.authelia.${name};
          owner = "authelia-main";
          group = "authelia-main";
        };
      })
      [
        "jwt"
        "ldap"
        "session"
        "storage"
        "oidc-cert"
        "oidc-hmac"
      ]
  );
  systemd.services."authelia-main" = {
    serviceConfig = {
      LoadCredential = [
        "ldap_password:${config.vaultix.secrets.authelia-ldap.path}"
      ];
    };
  };

  services.authelia.instances."main" = {
    enable = true;

    secrets = {
      jwtSecretFile = config.vaultix.secrets.authelia-jwt.path;
      sessionSecretFile = config.vaultix.secrets.authelia-session.path;
      storageEncryptionKeyFile = config.vaultix.secrets.authelia-storage.path;
      oidcIssuerPrivateKeyFile = config.vaultix.secrets.authelia-oidc-cert.path;
      oidcHmacSecretFile = config.vaultix.secrets.authelia-oidc-hmac.path;
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
        rules = config.myAuthelia.accessRules ++ [
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

      identity_providers.oidc.clients = config.myAuthelia.oidcClients;
    };
  };
}
