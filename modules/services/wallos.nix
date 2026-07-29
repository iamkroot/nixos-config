{
  config,
  pii,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "wallos" { authelia = false; })
  ];

  vaultix.secrets.wallos_sso_secret = {
    file = pii.secrets.wallos-sso-secret;
  };

  vaultix.templates."wallos.env" = {
    content = ''
      TZ=America/Los_Angeles
      OIDC_ENABLED=true
      OIDC_PROVIDER_NAME=Authelia
      OIDC_CLIENT_ID=${pii.secrets.authelia-wallos-client-id}
      OIDC_CLIENT_SECRET=${config.vaultix.placeholder.wallos_sso_secret}
      OIDC_ISSUER=https://${config.infra.services.hostnames.auth}
      OIDC_USER_IDENTIFIER=preferred_username
      OIDC_AUTO_CREATE_USER=true
      OIDC_REDIRECT_URL=https://${config.infra.services.hostnames.wallos}/index.php
      SSRF_ALLOWLIST=${config.infra.services.hostnames.auth}
    '';
  };

  virtualisation.oci-containers.containers."wallos" = {
    image = "docker.io/bellamy/wallos:latest";
    ports = [ "127.0.0.1:${toString config.infra.services.ports.wallos}:80" ];
    volumes = [
      "/var/lib/wallos/db:/var/www/html/db"
      "/var/lib/wallos/logos:/var/www/html/images/uploads/logos"
    ];
    extraOptions = [
      "--add-host=${config.infra.services.hostnames.auth}:host-gateway"
    ];
    environmentFiles = [
      config.vaultix.templates."wallos.env".path
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/wallos 0755 root root -"
    "d /var/lib/wallos/db 0777 root root -"
    "d /var/lib/wallos/logos 0777 root root -"
  ];
}
