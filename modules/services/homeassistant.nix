{
  config,
  lib,
  pkgs,
  services,
  myUtils,
  ...
}:
let
  port = config.infra.services.ports.homeassistant;
  smartrentSrc = myUtils.fetchRepo pkgs config.infra.versions.homeassistant-smartrent.src;
in
{
  imports = [
    (myUtils.mkCaddyModule "homeassistant" {
      authelia = false;
      # FIXME: Need to ensure api is still available
    })
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers."homeassistant" = {
    image = myUtils.mkImage config.infra.versions.homeassistant;
    ports = [ "127.0.0.1:${toString port}:8123" ];
    volumes = [
      "/var/lib/homeassistant:/config"
      "/etc/localtime:/etc/localtime:ro"
      "${smartrentSrc}/custom_components/smartrent:/config/custom_components/smartrent:ro"
    ];
    environment = {
      TZ = "America/Los_Angeles";
    };
    extraOptions = [
      "--health-interval=5m"
      "--health-retries=3"
      "--add-host=host.containers.internal:host-gateway"
    ]
    ++ lib.optional (
      services ? dawarich
    ) "--add-host=${config.infra.services.hostnames.dawarich}:host-gateway";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/homeassistant 0755 root root -"
  ];
}
