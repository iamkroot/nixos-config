{
  config,
  pii,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "obsidian-live-sync" { authelia = false; })
  ];

  vaultix.secrets.obsidian_livesync_pwd = {
    file = pii.secrets.obsidian-livesync-pwd;
    owner = "couchdb";
    group = "couchdb";
  };
  vaultix.secrets.obsidian_livesync_user = {
    file = pii.secrets.obsidian-livesync-user;
    owner = "couchdb";
    group = "couchdb";
  };

  vaultix.templates."obsidian_couchdb.ini" = {
    content = ''
      [admins]
      ${config.vaultix.placeholder.obsidian_livesync_user} = ${config.vaultix.placeholder.obsidian_livesync_pwd}
    '';
    owner = "couchdb";
    group = "couchdb";
  };

  services.couchdb = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = config.infra.services.ports.obsidian-live-sync;
    extraConfigFiles = [
      config.vaultix.templates."obsidian_couchdb.ini".path
    ];
    extraConfig = {
      couchdb = {
        max_document_size = "100000000";
      };
      chttpd = {
        require_valid_user = "true";
        max_http_request_size = "4294967296";
        enable_cors = "true";
      };
      chttpd_auth = {
        require_valid_user = "true";
        authentication_redirect = "/launder/_utils/session.html";
      };
      httpd = {
        "WWW-Authenticate" = "Basic realm=\"couchdb\"";
      };
      cors = {
        origins = "app://obsidian.md,capacitor://localhost,http://localhost";
        credentials = "true";
        headers = "accept, authorization, content-type, origin, referer";
        methods = "GET,PUT,POST,HEAD,DELETE";
        max_age = "3600";
      };
    };
  };
}
