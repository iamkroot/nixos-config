{
  config,
  pkgs,
  lib,
  pii,
  myUtils,
  inputs,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "suggestarr" { authelia = true; })
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/suggestarr 0755 root root - -"
    "d /var/lib/suggestarr/config_files 0755 root root - -"
  ];

  systemd.services.suggestarr-build = {
    description = "Build SuggestArr Image";
    path = [
      pkgs.podman
      pkgs.git
    ];
    after = [
      "network-online.target"
      "local-fs.target"
    ];
    requires = [
      "network-online.target"
      "local-fs.target"
    ];
    environment = {
      CONTAINERS_REGISTRIES_CONF = pkgs.writeText "registries.conf" ''
        unqualified-search-registries = ["docker.io"]
      '';
    };
    script = ''
      cd ${inputs.suggestarr}
      podman build -t suggestarr-local:latest -f docker/Dockerfile .
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      TimeoutStartSec = "10m";
    };
  };

  systemd.services."podman-suggestarr" = {
    requires = [ "suggestarr-build.service" ];
    after = [ "suggestarr-build.service" ];
  };

  virtualisation.oci-containers.containers.suggestarr = {
    image = "suggestarr-local:latest";
    ports = [ "${toString config.infra.services.ports.suggestarr}:5000" ];

    extraOptions = [
      "--add-host=jellyfin.kroot.dev:host-gateway"
    ];

    volumes = [
      "/var/lib/suggestarr/config_files:/app/config/config_files:rw"
    ];

    environment = {
      SUGGESTARR_PORT = "5000";
    };
  };
}
