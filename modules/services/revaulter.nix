{
  config,
  pkgs,
  myUtils,
  ...
}:
let
  domain = "https://${config.infra.services.hostnames.revaulter}";
  yamlFormat = pkgs.formats.yaml { };
  revaulterConfig = yamlFormat.generate "revaulter.yaml" {
    databaseDSN = "/data/revaulter.db";
    baseUrl = domain;
    forceSecureCookies = true;
    disableSignup = true;
  };
in
{
  imports = [
    (myUtils.mkCaddyModule "revaulter" { authelia = false; })
  ];

  virtualisation.oci-containers.containers."revaulter" = {
    image = "ghcr.io/italypaleale/revaulter:2.4.1";
    ports = [ "127.0.0.1:${toString config.infra.services.ports.revaulter}:8080" ];
    volumes = [
      "revaulter-data:/data"
      "${revaulterConfig}:/etc/revaulter/config.yaml:ro"
    ];
    environmentFiles = [
      config.vaultix.templates."revaulter.env".path
    ];
  };

  vaultix.secrets."revaulter/secret_key" = { };
  vaultix.secrets."revaulter/session_signing_key" = { };
  vaultix.secrets."revaulter/webhook_format" = { };
  vaultix.secrets."revaulter/webhook_key" = { };
  vaultix.secrets."revaulter/webhook_url" = { };

  vaultix.templates."revaulter.env" = {
    content = ''
      REVAULTER_SECRETKEY=${config.vaultix.placeholder."revaulter/secret_key"}
      REVAULTER_SESSIONSIGNINGKEY=${config.vaultix.placeholder."revaulter/session_signing_key"}
      REVAULTER_WEBHOOKURL=${config.vaultix.placeholder."revaulter/webhook_url"}
      REVAULTER_WEBHOOKKEY=${config.vaultix.placeholder."revaulter/webhook_key"}
      REVAULTER_WEBHOOKFORMAT=${config.vaultix.placeholder."revaulter/webhook_format"}
    '';
  };
}
