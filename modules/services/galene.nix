{
  config,
  lib,
  pii,
  myUtils,
  ...
}:
let
  galenePort = config.infra.services.ports.galene;
  udpPort = config.infra.services.ports.galene_udp;
  turnPort = config.infra.services.ports.coturn;
  turnHostname = config.infra.services.hostnames.coturn;
  hostname = config.infra.services.hostnames.galene;
in
{
  imports = [
    (myUtils.mkCaddyModule "galene" {
      authelia = true;
      bypassAuthPaths = [
        "/group/*"
        "/ws"
        "/*.js"
        "/*.css"
        "/*.ico"
        "/*.png"
        "/*.svg"
        "/*.json"
        "/sounds/*"
        "/static/*"
        "/third-party/*"
      ];
    })
  ];

  myAuthelia.accessRules = [
    {
      domain = [ hostname ];
      policy = "one_factor";
      subject = [
        "group:basic_users"
        "group:lldap_admin"
      ];
    }
  ];

  vaultix.secrets."galene/admin_password".file = "${pii.secrets.galene-admin-password}";
  vaultix.secrets."coturn/auth_secret" = { };

  vaultix.templates."galene-config.json" = {
    path = "/var/lib/galene/data/config.json";
    owner = "galene";
    group = "galene";
    mode = "0640";
    content = builtins.toJSON {
      users = {
        "${pii.primaryUser}" = {
          password = config.vaultix.placeholder."galene/admin_password";
          permissions = "admin";
        };
      };
      canonicalHost = hostname;
      proxyURL = "https://${hostname}";
      writableGroups = true;
    };
  };

  vaultix.templates."galene-general-group.json" = {
    path = "/var/lib/galene/groups/general.json";
    owner = "galene";
    group = "galene";
    mode = "0640";
    content = builtins.toJSON {
      public = true;
      displayName = "General";
      description = "General meeting room";
      allow-recording = true;
      users = {
        "${pii.primaryUser}" = {
          password = config.vaultix.placeholder."galene/admin_password";
          permissions = "op";
        };
      };
    };
  };

  vaultix.templates."galene-ice-servers.json" = {
    path = "/var/lib/galene/data/ice-servers.json";
    owner = "galene";
    group = "galene";
    mode = "0640";
    content = builtins.toJSON [
      {
        urls = [
          "stun:${turnHostname}:${toString turnPort}"
          "turn:${turnHostname}:${toString turnPort}"
          "turn:${turnHostname}:${toString turnPort}?transport=tcp"
        ];
        username = "galene";
        credential = config.vaultix.placeholder."coturn/auth_secret";
        credentialType = "hmac-sha1";
      }
    ];
  };

  services.galene = {
    enable = true;
    insecure = true;
    httpAddress = "127.0.0.1";
    httpPort = galenePort;
    turnAddress = "";
  };

  systemd.services.galene = {
    after = [
      "network.target"
      "vaultix-activate.service"
      "disko-zfs.service"
    ];
    wants = [ "vaultix-activate.service" ];
    serviceConfig = {
      RestartSec = 2;
      ExecStart = lib.mkForce ''
        ${config.services.galene.package}/bin/galene \
          -insecure \
          -http ${config.services.galene.httpAddress}:${toString galenePort} \
          -turn= \
          -udp-range ${toString udpPort} \
          -data ${config.services.galene.dataDir} \
          -groups ${config.services.galene.groupsDir} \
          -recordings ${config.services.galene.recordingsDir} \
          -static ${config.services.galene.staticDir}
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/galene 0750 galene galene -"
    "d /var/lib/galene/data 0750 galene galene -"
    "d /var/lib/galene/groups 0750 galene galene -"
    "d /var/lib/galene/recordings 0750 galene galene -"
  ];

  networking.firewall.allowedUDPPorts = [ udpPort ];
}
