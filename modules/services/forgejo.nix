{
  config,
  pii,
  pkgs,
  myUtils,
  lib,
  ...
}:
let
  sshPort = config.infra.services.ports.forgejo_ssh;
in
{
  imports = [
    (myUtils.mkCaddyModule "forgejo" { authelia = false; })
  ];

  myAuthelia.oidcClients = [
    (myUtils.mkAutheliaOIDC pii "forgejo" {
      scopes = [
        "openid"
        "profile"
        "email"
        "groups"
      ];
      redirect_uris = [
        "https://${config.infra.services.hostnames.forgejo}/user/oauth2/Authelia/callback"
      ];
      token_endpoint_auth_method = "client_secret_basic";
    })
  ];

  vaultix.secrets."forgejo_sso_secret" = {
    file = pii.secrets.forgejo-sso-secret;
    owner = "forgejo";
    group = "forgejo";
  };

  vaultix.secrets."forgejo_admin_pwd" = {
    owner = "forgejo";
    group = "forgejo";
  };

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    database.type = "sqlite3";
    lfs.enable = true;
    settings = {
      server = {
        HTTP_PORT = config.infra.services.ports.forgejo;
        HTTP_ADDR = "127.0.0.1";
        DOMAIN = config.infra.services.hostnames.forgejo;
        ROOT_URL = "https://${config.infra.services.hostnames.forgejo}/";
        START_SSH_SERVER = true;
        SSH_PORT = sshPort;
        SSH_LISTEN_PORT = sshPort;
        BUILTIN_SSH_SERVER_USER = "git";
      };
      service = {
        DISABLE_REGISTRATION = true;
        ENABLE_PASSWORD_SIGNIN_FORM = false;
        ENABLE_BASIC_AUTHENTICATION = false;
      };
    };
  };

  systemd.services.forgejo = {
    after = [
      "authelia-main.service"
      "caddy.service"
    ];
    wants = [
      "authelia-main.service"
      "caddy.service"
    ];
  };

  networking.firewall.allowedTCPPorts = [ sshPort ];
  systemd.services.forgejo.preStart =
    let
      adminCmd = "${lib.getExe config.services.forgejo.package} admin";
      adminUser = pii.primaryUser;
      adminEmail = pii.primaryEmail;
      adminPwd = config.vaultix.secrets."forgejo_admin_pwd".path;
      oidcName = "Authelia";
      ssoSecretFile = config.vaultix.secrets."forgejo_sso_secret".path;
      clientId = pii.authelia.forgejo.client-id;
      autoDiscoverUrl = "https://${config.infra.services.hostnames.auth}/.well-known/openid-configuration";
    in
    ''
      # Get the ID of the existing auth source, if any
      OAUTH_ID=$(${adminCmd} auth list | ${pkgs.gnugrep}/bin/grep -E "[[:space:]]${oidcName}[[:space:]]" | ${pkgs.gawk}/bin/awk '{print $1}' || true)

      if [ -z "$OAUTH_ID" ]; then
        ${adminCmd} auth add-oauth \
          --name ${oidcName} \
          --provider openidConnect \
          --key "${clientId}" \
          --secret "$(${pkgs.coreutils}/bin/cat ${ssoSecretFile})" \
          --auto-discover-url "${autoDiscoverUrl}"
      else
        ${adminCmd} auth update-oauth \
          --id "$OAUTH_ID" \
          --key "${clientId}" \
          --secret "$(${pkgs.coreutils}/bin/cat ${ssoSecretFile})" \
          --auto-discover-url "${autoDiscoverUrl}"
      fi

      # create admin user
      ${adminCmd} user create --admin --email "${adminEmail}" --username ${adminUser} --must-change-password=false --password "$(${pkgs.coreutils}/bin/tr -d '\n' < ${adminPwd})" || true
    '';
}
