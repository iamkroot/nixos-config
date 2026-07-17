{
  config,
  ...
}:
{

  virtualisation.oci-containers.containers.byparr = {
    image = "ghcr.io/thephaseless/byparr:latest";
    ports = [ "${toString config.infra.services.ports.byparr}:8191" ];

    environment = {
      PORT = "8191";
      HOST = "0.0.0.0";
    };

    extraOptions = [
      "--health-interval=5m"
      "--health-retries=3"
      "--dns=1.1.1.1"
      "--dns=1.0.0.1"
    ];
  };

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    config.infra.services.ports.byparr
  ];
}
