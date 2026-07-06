{ config, pkgs, myUtils, pii, ... }:
let
  domain = "https://${config.infra.services.hostnames.revaulter}";
in
{
  imports = [
    (myUtils.mkCaddyModule "revaulter" { authelia = false; })
  ];

  virtualisation.oci-containers.containers."revaulter" = {
    image = "ghcr.io/italypaleale/revaulter:2";
    ports = [ "127.0.0.1:${toString config.infra.services.ports.revaulter}:8080" ];
    volumes = [
      "revaulter-data:/data"
    ];
    environment = {
      REVAULTER_DATABASEDSN = "/data/revaulter.db";
      REVAULTER_BASEURL = domain;
      REVAULTER_FORCESECURECOOKIES = "true";
      REVAULTER_DISABLESIGNUP = "true";
    };
    environmentFiles = [
      config.vaultix.templates."revaulter.env".path
    ];
  };

  vaultix.secrets."revaulter/secret_key" = { };
  vaultix.secrets."revaulter/session_signing_key" = { };

  vaultix.templates."revaulter.env" = {
    content = ''
      REVAULTER_SECRETKEY=''${config.vaultix.placeholder."revaulter/secret_key"}
      REVAULTER_SESSIONSIGNINGKEY=''${config.vaultix.placeholder."revaulter/session_signing_key"}
    '';
  };
}
