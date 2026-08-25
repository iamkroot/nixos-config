{
  config,
  pii,
  myUtils,
  pkgs,
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

  systemd.services.couchdb-init-db = {
    description = "Initialize CouchDB System Databases for Obsidian LiveSync";
    after = [ "couchdb.service" ];
    requires = [ "couchdb.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
    script = ''
      ADMIN_USER="$(${pkgs.coreutils}/bin/cat ${config.vaultix.secrets.obsidian_livesync_user.path})"
      ADMIN_PWD="$(${pkgs.coreutils}/bin/cat ${config.vaultix.secrets.obsidian_livesync_pwd.path})"
      PORT="${toString config.infra.services.ports.obsidian-live-sync}"

      # 1. Wait for CouchDB HTTP listener to become ready (max 30s)
      for i in $(${pkgs.coreutils}/bin/seq 1 30); do
        if ${pkgs.curl}/bin/curl -s -f "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done

      # 2. Provision essential system databases
      for db in _users _replicator _global_changes; do
        ${pkgs.curl}/bin/curl -s -f -X PUT "http://$ADMIN_USER:$ADMIN_PWD@127.0.0.1:$PORT/$db" || true
      done
    '';
  };
}
