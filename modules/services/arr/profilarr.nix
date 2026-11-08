{
  config,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "profilarr" {
      authelia = true;
    })
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/profilarr 0770 root media - -"
  ];

  virtualisation.oci-containers.containers.profilarr = {
    image = myUtils.mkImage config.infra.versions.profilarr;
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

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    config.infra.services.ports.profilarr
  ];

  myAuthelia.accessRules = [
    # Require jellyfin_admins for Profilarr
    {
      domain = config.infra.services.hostnames.profilarr;
      policy = "one_factor";
      subject = [
        "group:jellyfin_admins"
      ];
    }
  ];
}
