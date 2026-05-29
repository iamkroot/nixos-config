{
  config,
  pkgs,
  lib,
  pii,
  myUtils,
  ...
}:
{
  imports = [
    # TODO: Doesn't support OIDC yet https://github.com/seerr-team/seerr/pull/2715
    (myUtils.mkCaddyModule "seerr" { authelia = false; })
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
}
