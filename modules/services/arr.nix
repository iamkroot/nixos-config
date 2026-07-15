{
  config,
  pii,
  myUtils,
  ...
}:
let
  downloadsDir = "${pii.storage.media_main.mountpoint}/Downloads";
in
{
  imports = [
    (myUtils.mkCaddyModule "radarr" { authelia = true; })
    (myUtils.mkCaddyModule "sonarr" { authelia = true; })
    (myUtils.mkCaddyModule "decypharr" { authelia = true; })
    (myUtils.mkCaddyModule "profilarr" { authelia = true; })
    (myUtils.mkCaddyModule "prowlarr" { authelia = true; })
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

  services.radarr = {
    enable = true;
    group = "media";
    environmentFiles = [ "/var/lib/radarr/radarr.env" ];
    settings = {
      server.port = config.infra.services.ports.radarr;
      auth.method = "External";
    };
  };

  # TODO: Is there a way to declare sonarr/radarr App configs here?
  services.prowlarr = {
    enable = true;
    settings = {
      server.port = config.infra.services.ports.prowlarr;
      auth.method = "External";
    };
  };

  # Use systemd tmpfiles to apply ACLs to the Downloads folder
  # This ensures the 'media' group always has access to files created by the container
  systemd.tmpfiles.rules = [
    "d /var/lib/decypharr 0770 root media - -"
    "d /var/lib/profilarr 0770 root media - -"
    "d ${downloadsDir} 2775 root media - -"
    "A ${downloadsDir} - - - - default:group:media:rwx"
  ];

  virtualisation.oci-containers.containers.decypharr = {
    image = "cy01/blackhole:latest";
    ports = [ "${toString config.infra.services.ports.decypharr}:8282" ];

    # Tell Decypharr to run as host's user/group IDs
    environment = {
      PUID = "1000";
      PGID = toString config.users.groups.media.gid;
    };

    volumes = [
      "/var/lib/decypharr:/var/lib/decypharr:rw"
      "${downloadsDir}:${downloadsDir}:rw"
      # FIXME: Should not rw directly to vaultix path. Doing so to ensure decypharr doesn't fail to update settings
      "${config.vaultix.templates."decypharr-config.json".path}:/app/config.json:rw"
    ];

    extraOptions = [
      "--health-interval=5m"
      "--health-retries=3"
    ];
  };

  virtualisation.oci-containers.containers.profilarr = {
    image = "ghcr.io/dictionarry-hub/profilarr:latest";
    ports = [ "${toString config.infra.services.ports.profilarr}:6868" ];

    environment = {
      PUID = "1000";
      PGID = toString config.users.groups.media.gid;
      # handled by authelia
      AUTH = "off";
      ORIGIN = "https://${config.infra.services.hostnames.profilarr}";
    };

    volumes = [
      "/var/lib/profilarr:/config:rw"
    ];

    extraOptions = [
      "--health-interval=5m"
      "--health-retries=3"
      # Bypass Hairpin NAT bugs, map the public domain to host
      "--add-host=${config.infra.services.hostnames.radarr}:host-gateway"
      "--add-host=${config.infra.services.hostnames.sonarr}:host-gateway"
    ];
  };

  vaultix.secrets."debrid-key" = {
    file = pii.secrets.debrid-key;
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

  networking.firewall.interfaces."podman0".allowedTCPPorts =
    map (name: config.infra.services.ports.${name})
      [
        "radarr"
        "sonarr"
        "prowlarr"
        "profilarr"
        "aria2" # FIXME: Move this closer to aria2 module
      ];

  vaultix.templates."decypharr-config.json" = {
    group = "media";
    mode = "660";
    content = ''
      {
        "debrids": [
          {
            "provider": "${pii.debridProvider}",
            "name": "${pii.debridProvider}",
            "api_key": "${config.vaultix.placeholder."debrid-key"}",
            "download_api_keys": [
              "${config.vaultix.placeholder."debrid-key"}"
            ],
            "rate_limit": "250/minute",
            "minimum_free_slot": 1,
            "torrents_refresh_interval": "10m",
            "download_links_refresh_interval": "5m",
            "workers": 600,
            "auto_expire_links_after": "3d"
          }
        ],
        "download_folder": "${downloadsDir}",
        "remove_stalled_after": "10m",
        "notifications": {},
        "refresh_interval": "30s",
        "max_downloads": 10,
        "categories": [
          "sonarr",
          "radarr"
        ],
        "folder_naming": "original_no_ext",
        "default_download_action": "download",
        "retries": 3,
        "repair": {
          "source": "arr",
          "workers": 5,
          "nntp_connection_percent": 20,
          "strategy": "per_entry",
          "recheck_interval": "168h"
        },
        "mount": {
          "type": "none",
          "mount_path": "."
        },
        "arrs": [
          {
            "name": "Sonarr",
            "host": "http://host.containers.internal:${toString config.infra.services.ports.sonarr}",
            "token": "${config.vaultix.placeholder.sonarr-key}",
            "download_action": "download"
          },
          {
            "name": "Radarr",
            "host": "http://host.containers.internal:${toString config.infra.services.ports.radarr}",
            "token": "${config.vaultix.placeholder.radarr-key}",
            "download_action": "download"
          }
        ]
      }
    '';
  };
}
