{
  config,
  pkgs,
  myUtils,
  pii,
  ...
}:
let
  arrImportExtras = import ./import-extras-pkg.nix { inherit pkgs; };
in
{
  imports = [
    (myUtils.mkCaddyModule "sonarr" {
      authelia = true;
    })
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sonarr/custom-scripts 0755 sonarr media - -"
    "L+ /var/lib/sonarr/custom-scripts/sonarr-import-extras - - - - ${arrImportExtras}/bin/arr-import-extras"
    "L+ /var/lib/sonarr/custom-scripts/arr-import-extras - - - - ${arrImportExtras}/bin/arr-import-extras"
  ];

  services.sonarr = {
    enable = true;
    group = "media";
    environmentFiles = [ "/var/lib/sonarr/sonarr.env" ];
    settings = {
      server.port = config.infra.services.ports.sonarr;
      auth.method = "External";
    };
  };

  vaultix.secrets."sonarr-key" = {
    file = pii.secrets.sonarr-key;
  };

  vaultix.templates."sonarr.env" = {
    content = ''
      SONARR_AUTH_APIKEY=${config.vaultix.placeholder.sonarr-key}
    '';
    mode = "640";
    group = "media";
    path = "/var/lib/sonarr/sonarr.env";
  };

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    config.infra.services.ports.sonarr
  ];

  myAuthelia.accessRules = [
    {
      domain = [ config.infra.services.hostnames.sonarr ];
      resources = [ "^/api.*" ];
      policy = "bypass";
    }
  ];
}
