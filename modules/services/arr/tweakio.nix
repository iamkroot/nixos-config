{
  config,
  pii,
  myUtils,
  ...
}:
{
  virtualisation.oci-containers.containers.tweakio = {
    image = myUtils.mkImage config.infra.versions.tweakio;
    ports = [ "${toString config.infra.services.ports.tweakio}:3185" ];

    environmentFiles = [
      config.vaultix.templates."tweakio.env".path
    ];

    extraOptions = [
      "--health-interval=5m"
      "--health-retries=3"
    ];
  };

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    config.infra.services.ports.tweakio
  ];

  vaultix.secrets."tmdb-key" = {
    file = pii.secrets.tmdb-key;
  };

  vaultix.templates."tweakio.env" = {
    content = ''
      TMDB_API_KEY=${config.vaultix.placeholder.tmdb-key}
    '';
  };
}
