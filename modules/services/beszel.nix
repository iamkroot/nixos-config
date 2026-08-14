{
  config,
  lib,
  myUtils,
  pii,
  pkgs,
  ...
}:
let
  hubPort = config.infra.services.ports.beszel;
in
{
  imports = [
    (myUtils.mkCaddyModule "beszel" { authelia = true; })
  ];

  vaultix.secrets."beszel/hub_private_key" = {
    path = "/var/lib/private/beszel-hub/beszel_data/id_ed25519";
    mode = "0600";
    owner = "beszel-hub";
    group = "beszel-hub";
  };
  vaultix.secrets."beszel/admin_password" = { };

  myAuthelia.oidcClients = [
    (myUtils.mkAutheliaOIDC pii "beszel" {
      redirect_uris = [
        "https://${config.infra.services.hostnames.beszel}/api/oauth2-redirect"
      ];
    })
  ];

  vaultix.templates."beszel-hub.env" = {
    content = ''
      USER_EMAIL=${pii.primaryEmail}
      USER_PASSWORD=${config.vaultix.placeholder."beszel/admin_password"}
      USER_CREATION=false
    '';
  };

  # Native Beszel Hub
  services.beszel.hub = {
    enable = true;
    host = "127.0.0.1";
    port = hubPort;
  };

  systemd.services.beszel-hub.serviceConfig = {
    # Fix broken `history-sync` subcommand bug in current nixpkgs beszel-hub module
    ExecStartPre = lib.mkForce [
      "${pkgs.beszel}/bin/beszel-hub migrate up"
    ];
    # Prefix with '-' so systemd doesn't fail to start if secret file is not yet provisioned
    EnvironmentFile = lib.mkForce [
      "-${config.vaultix.templates."beszel-hub.env".path}"
    ];
  };
}
