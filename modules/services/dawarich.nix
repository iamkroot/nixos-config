{
  config,
  pkgs,
  pii,
  myUtils,
  ...
}:
let
  dawarichPkg = myUtils.selfExpiringOverride {
    inherit pkgs;
    name = "dawarich";
    localPkg = pkgs.callPackage ../../pkgs/dawarich { };
  };
in
{
  imports = [
    (myUtils.mkCaddyModule "dawarich" { authelia = false; })
  ];

  myAuthelia.accessRules = [
    {
      domain = config.infra.services.hostnames.dawarich;
      policy = "one_factor";
      subject = [
        "group:dawarich_users"
      ];
    }
  ];

  myAuthelia.oidcClients = [
    (myUtils.mkAutheliaOIDC pii "dawarich" {
      redirect_uris = [
        "https://${config.infra.services.hostnames.dawarich}/users/auth/openid_connect/callback"
      ];
      scopes = [
        "openid"
        "profile"
        "email"
      ];
      token_endpoint_auth_method = "client_secret_basic";
    })
  ];

  vaultix.secrets."dawarich_sso_secret" = {
    file = pii.secrets.dawarich-sso-secret;
    owner = "dawarich";
    group = "dawarich";
  };

  vaultix.templates."dawarich.env" = {
    owner = "dawarich";
    group = "dawarich";
    content = ''
      OIDC_ENABLED=true
      OIDC_CLIENT_ID=${pii.authelia.dawarich.client-id}
      OIDC_CLIENT_SECRET=${config.vaultix.placeholder.dawarich_sso_secret}
      OIDC_ISSUER=https://${config.infra.services.hostnames.auth}
      OIDC_REDIRECT_URI=https://${config.infra.services.hostnames.dawarich}/users/auth/openid_connect/callback
    '';
  };

  services.dawarich = {
    enable = true;
    package = dawarichPkg;
    configureNginx = false;
    webPort = config.infra.services.ports.dawarich;
    localDomain = config.infra.services.hostnames.dawarich;

    database = {
      createLocally = true;
      port = config.infra.services.ports.postgres;
    };
    redis.createLocally = true;
    automaticMigrations = true;

    extraEnvFiles = [
      config.vaultix.templates."dawarich.env".path
    ];
  };
}
