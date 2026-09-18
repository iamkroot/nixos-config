{
  config,
  lib,
  services,
  myUtils,
  ...
}:
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
    image = "ghcr.io/home-assistant/home-assistant:2026.9.3@sha256:d8922685169707fd91e8b9729902d975f06157d005e422874d201e0261dda196";
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
    ]
    ++ lib.optional (
      services ? dawarich
    ) "--add-host=${config.infra.services.hostnames.dawarich}:host-gateway";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/homeassistant 0755 root root -"
  ];
}
