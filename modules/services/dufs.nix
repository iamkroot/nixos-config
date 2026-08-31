{
  config,
  pkgs,
  pii,
  myUtils,
  ...
}:
let
  port = config.infra.services.ports.dufs;
in
{
  imports = [
    (myUtils.mkCaddyModule "dufs" { authelia = false; })
  ];

  vaultix.secrets."dufs/password" = { };

  vaultix.templates."dufs.yaml" = {
    path = "/var/lib/dufs/dufs.yaml";
    owner = "dufs";
    group = "dufs";
    mode = "0440";
    content = ''
      allow-all: true
      enable-cors: true
      auth:
        - "${pii.primaryUser}:${config.vaultix.placeholder."dufs/password"}@/:rw"
    '';
  };

  users.users.dufs = {
    isSystemUser = true;
    group = "dufs";
    extraGroups = [ "media" ];
  };
  users.groups.dufs = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/dufs 0750 dufs dufs - -"
    "d ${pii.davDir} 0775 dufs media - -"
    "z ${pii.davDir} 0775 dufs media - -"
    "A ${pii.davDir} - - - - group:media:rwx"
    "A ${pii.davDir} - - - - default:group:media:rwx"
  ];

  systemd.services.dufs = {
    description = "Dufs WebDAV & File Server";
    after = [
      "network.target"
      "vaultix-activate.service"
    ];
    wants = [ "vaultix-activate.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "dufs";
      Group = "dufs";
      SupplementaryGroups = [ "media" ];
      ExecStart = "${pkgs.dufs}/bin/dufs --config ${
        config.vaultix.templates."dufs.yaml".path
      } --bind 127.0.0.1 --port ${toString port} ${pii.davDir}";
      Restart = "always";
      RestartSec = "5s";
      LimitNOFILE = 65536;
    };
  };
}
