{
  config,
  myUtils,
  ...
}:
let
  port = config.infra.services.ports.waha;
in
{
  imports = [
    (myUtils.mkCaddyModule "waha" {
      authelia = false;
      meshOnly = true;
    })
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.oci-containers.backend = "podman";

  vaultix.secrets."waha/api_key" = { };
  vaultix.secrets."waha/dashboard_password" = { };

  vaultix.templates."waha.env" = {
    content = ''
      WAHA_API_KEY=${config.vaultix.placeholder."waha/api_key"}
      WAHA_DASHBOARD_USERNAME=admin
      WAHA_DASHBOARD_PASSWORD=${config.vaultix.placeholder."waha/dashboard_password"}
      WHATSAPP_SWAGGER_USERNAME=admin
      WHATSAPP_SWAGGER_PASSWORD=${config.vaultix.placeholder."waha/dashboard_password"}
    '';
  };

  virtualisation.oci-containers.containers."waha" = {
    image = "docker.io/devlikeapro/waha:gows";
    ports = [ "127.0.0.1:${toString port}:3000" ];
    environment = {
      WHATSAPP_DEFAULT_ENGINE = "GOWS";
      WAHA_PRINT_QR = "false";
      WAHA_DASHBOARD_ENABLED = "true";
    };
    environmentFiles = [
      config.vaultix.templates."waha.env".path
    ];
    volumes = [
      "/var/lib/waha/sessions:/app/.sessions"
      "/var/lib/waha/media:/app/.media"
    ];
    extraOptions = [
      "--no-healthcheck"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/waha 0755 root root -"
    "d /var/lib/waha/sessions 0777 root root -"
    "d /var/lib/waha/media 0777 root root -"
  ];
}
