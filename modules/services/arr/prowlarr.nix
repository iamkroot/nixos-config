{
  config,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "prowlarr" {
      authelia = true;
    })
  ];

  # TODO: Is there a way to declare sonarr/radarr App configs here?
  services.prowlarr = {
    enable = true;
    settings = {
      server.port = config.infra.services.ports.prowlarr;
      auth.method = "External";
    };
  };

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    config.infra.services.ports.prowlarr
  ];
}
