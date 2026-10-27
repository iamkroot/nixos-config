{
  config,
  pii,
  myUtils,
  ...
}:
let
  port = config.infra.services.ports."prowlarr-orionoid";
in
{
  virtualisation.oci-containers.containers.prowlarr-orionoid = {
    image = myUtils.mkImage config.infra.versions.prowlarr-orionoid;
    ports = [
      "127.0.0.1:${toString port}:8080"
    ];

    volumes = [
      "${./prowlarr-orionoid/torznab_builder.py}:/app/torznab_builder.py:ro"
    ];

    environmentFiles = [
      config.vaultix.templates."prowlarr-orionoid.env".path
    ];

    environment = {
      SERVICE_PORT = "8080";
      SERVICE_HOST = "0.0.0.0";
    };

    extraOptions = [
      "--health-interval=5m"
      "--health-retries=3"
    ];
  };

  vaultix.secrets."orionoid-key" = {
    file = pii.secrets.orionoid-key;
  };

  vaultix.templates."prowlarr-orionoid.env" = {
    content = ''
      ORIONOID_USER_API_KEY=${config.vaultix.placeholder.orionoid-key}
    '';
  };
}
