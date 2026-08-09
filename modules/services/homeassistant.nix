{ config, myUtils, ... }:
let
  port = config.infra.services.ports.homeassistant;
in
{
  imports = [
    (myUtils.mkCaddyModule "homeassistant" { authelia = false; })
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers."homeassistant" = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    ports = [ "127.0.0.1:${toString port}:8123" ];
    volumes = [
      "/var/lib/homeassistant:/config"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environment = {
      TZ = "America/Los_Angeles";
    };
    extraOptions = [
      "--health-interval=5m"
      "--health-retries=3"
      "--add-host=host.containers.internal:host-gateway"
      "--add-host=${config.infra.services.hostnames.dawarich}:host-gateway"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/homeassistant 0755 root root -"
  ];
}
