{
  config,
  pkgs,
  lib,
  myUtils,
  pii,
  ...
}:

let
  mediaGroupGid = config.users.groups.media.gid;

  # Helper to generate volume strings for Podman
  animeVolumes = lib.mapAttrsToList (name: path: "${path}:/mnt/anime/${name}") pii.media.animeDirs;
in
{
  imports = [
    # didn't find a way to setup authelia
    (myUtils.mkCaddyModule "shoko" { authelia = false; })
  ];
  virtualisation.podman.enable = true;

  users.users."${pii.primaryUser}".extraGroups = [ "podman" ];

  virtualisation.oci-containers = {
    backend = "podman";
    containers."shoko-server" = {
      image = "ghcr.io/shokoanime/server:latest";
      autoStart = true;
      ports = [ "${toString config.infra.services.ports.shoko}:8111" ];

      environment = {
        TZ = "America/Los_Angeles";
        PUID = "1000";
        PGID = toString mediaGroupGid;
      };

      volumes = [
        "/var/lib/shoko:/home/shoko/.shoko"
      ]
      ++ animeVolumes;

      extraOptions = [
        "--no-healthcheck"
      ];
    };
  };

  systemd.services.shoko-perms = {
    description = "Set permissions for Shoko ZFS mount";
    after = [ "var-lib-shoko.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/chown -R 1000:media /var/lib/shoko";
    };
  };
}
