{
  config,
  pkgs,
  myUtils,
  pii,
  ...
}:
let
  domain = "https://${config.infra.services.hostnames.vaultwarden}";
in
{
  imports = [
    (myUtils.mkCaddyModule "vaultwarden" { authelia = false; })
  ];
  infra.services.catalog.vaultwarden.icon =
    "https://${config.infra.services.hostnames.icons}/vaultwarden-light.svg";
  services.vaultwarden = {
    enable = true;
    environmentFile = config.vaultix.templates."vaultwarden.env".path;
    dbBackend = "sqlite";

    config = {
      DOMAIN = domain;
      SIGNUPS_ALLOWED = false;

      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = config.infra.services.ports.vaultwarden;
    };
  };
  vaultix.secrets."vaultwarden/admin_token" = { };
  vaultix.secrets."vaultwarden/sso_secret" = { };
  vaultix.secrets."vaultwarden/smtp_app_pwd" = { };
  vaultix.templates."vaultwarden.env" = {
    owner = "vaultwarden";
    group = "vaultwarden";
    content = ''
      ADMIN_TOKEN=${config.vaultix.placeholder."vaultwarden/admin_token"}

      SMTP_HOST=${pii.smtpHost}
      SMTP_FROM=${pii.smtpEmail}
      SMTP_FROM_NAME=Vaultwarden
      SMTP_PORT=587
      SMTP_SECURITY=starttls
      SMTP_USERNAME=${pii.smtpEmail}
      SMTP_PASSWORD=${config.vaultix.placeholder."vaultwarden/smtp_app_pwd"}

      SSO_ENABLED=true
      SSO_AUTHORITY=https://${config.infra.services.hostnames.auth}
      SSO_CLIENT_ID=${pii.secrets.authelia-vaultwarden-client-id}
      SSO_CLIENT_SECRET=${config.vaultix.placeholder."vaultwarden/sso_secret"}
      SSO_SIGNUPS_MATCH_EMAIL=true
    '';
  };
}
