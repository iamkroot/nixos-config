{
  config,
  myUtils,
  pii,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "radarr" {
      authelia = true;
    })
  ];

  services.radarr = {
    enable = true;
    group = "media";
    environmentFiles = [ "/var/lib/radarr/radarr.env" ];
    settings = {
      server.port = config.infra.services.ports.radarr;
      auth.method = "External";
    };
  };

  vaultix.secrets."radarr-key" = {
    file = pii.secrets.radarr-key;
  };

  vaultix.templates."radarr.env" = {
    content = ''
      RADARR_AUTH_APIKEY=${config.vaultix.placeholder.radarr-key}
    '';
    group = "media";
    mode = "640";
    path = "/var/lib/radarr/radarr.env";
  };

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    config.infra.services.ports.radarr
  ];

  myAuthelia.accessRules = [
    {
      domain = [ config.infra.services.hostnames.radarr ];
      resources = [ "^/api.*" ];
      policy = "bypass";
    }
  ];
}
