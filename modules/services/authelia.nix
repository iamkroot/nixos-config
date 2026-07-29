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
  ];

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
        rules = [
          # Bypass auth for Authelia itself
          {
            domain = config.infra.services.hostnames.auth;
            policy = "bypass";
          }
          {
            domain = config.infra.services.hostnames.vaultwarden;
            policy = "one_factor";
            subject = [
              "group:vaultwarden_users"
            ];
          }
          # Bypass API so *arr apps and external tools can talk to each other
          {
            domain = [
              config.infra.services.hostnames.seerr
              config.infra.services.hostnames.radarr
              config.infra.services.hostnames.sonarr
            ];
            resources = [ "^/api.*" ];
            policy = "bypass";
          }
          # Require auth for the human-facing web UI
          {
            domain = [ config.infra.services.hostnames.seerr ];
            policy = "one_factor";
          }
          # Require lldap_admin for Profilarr
          {
            domain = config.infra.services.hostnames.profilarr;
            policy = "one_factor";
            subject = [
              "group:lldap_admin"
            ];
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
        {
          client_id = pii.secrets.authelia-vaultwarden-client-id;
          client_secret = pii.secrets.authelia-vaultwarden-client-secret;
          client_name = "Vaultwarden";
          public = false;
          authorization_policy = "one_factor";
          redirect_uris = [
            "https://${config.infra.services.hostnames.vaultwarden}/identity/connect/oidc-signin"
          ];
          userinfo_signed_response_alg = "none";
        }
        {
          client_id = pii.secrets.authelia-immich-client-id;
          client_secret = pii.secrets.authelia-immich-client-secret;
          client_name = "Immich";
          public = false;
          authorization_policy = "one_factor";
          redirect_uris = [
            "https://${config.infra.services.hostnames.immich}/auth/login"
            "https://${config.infra.services.hostnames.immich}/user-settings"
            "app.immich:///oauth-callback"
          ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_post";
        }
        {
          client_id = pii.secrets.authelia-account-center-client-id;
          client_secret = pii.secrets.authelia-account-center-client-secret;
          client_name = "Account Center";
          public = false;
          authorization_policy = "one_factor";
          scopes = [
            "openid"
            "profile"
            "groups"
            "email"
            "offline_access"
          ];
          redirect_uris = [
            "https://${config.infra.services.hostnames."account-center"}/oidc-callback"
          ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_post";
        }
        {
          client_id = pii.secrets.authelia-wallos-client-id;
          client_secret = pii.secrets.authelia-wallos-client-secret;
          client_name = "Wallos";
          public = false;
          authorization_policy = "one_factor";
          redirect_uris = [
            "https://${config.infra.services.hostnames.wallos}/index.php"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
          ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_post";
        }
      ];
    };
  };
}
