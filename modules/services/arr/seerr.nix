{
  pkgs,
  config,
  myUtils,
  ...
}:
{
  imports = [
    # TODO: Doesn't support OIDC yet https://github.com/seerr-team/seerr/pull/2715
    (myUtils.mkCaddyModule "seerr" {
      authelia = false;
    })
  ];

  services.seerr = {
    enable = true;
    openFirewall = true;
  };

  users.users.seerr = {
    isSystemUser = true;
    group = "media";
  };

  # Needed to set perms on zfs created mountpoints
  systemd.services.seerr.serviceConfig.DynamicUser = pkgs.lib.mkForce false;

  systemd.tmpfiles.rules = [
    # Type | Path | Mode | User | Group | Age | Argument
    "d /var/lib/seerr 0755 seerr media -"
    "d /var/lib/seerr/db 0755 seerr media -"
    "d /var/lib/seerr/cache 0755 seerr media -"
    "d /var/lib/seerr/logs 0755 seerr media -"
  ];

  myAuthelia.accessRules = [
    # Bypass API so *arr apps and external tools can talk to each other
    {
      domain = [ config.infra.services.hostnames.seerr ];
      resources = [ "^/api.*" ];
      policy = "bypass";
    }
    # Require auth for the human-facing web UI
    {
      domain = [ config.infra.services.hostnames.seerr ];
      policy = "one_factor";
    }
  ];
}
