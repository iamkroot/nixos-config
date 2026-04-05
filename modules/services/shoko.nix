{
  config,
  pkgs,
  lib,
  pii,
  ...
}:

let
  mediaGroupGid = 995;

  # Helper to generate volume strings for Podman
  animeVolumes = lib.mapAttrsToList (name: path: "${path}:/mnt/anime/${name}") pii.media.animeDirs;
in
{
  virtualisation.podman.enable = true;

  users.users."${pii.primaryUser}".extraGroups = [ "podman" ];

  virtualisation.oci-containers = {
    backend = "podman";
    containers."shoko-server" = {
      image = "ghcr.io/shokoanime/server:latest";
      autoStart = true;
      ports = [ "8111:8111" ];

      environment = {
        TZ = "America/Los_Angeles";
        PUID = "1000";
        PGID = toString mediaGroupGid;
      };

      volumes = [
        "/var/lib/shoko:/home/shoko/.shoko"
      ]
      ++ animeVolumes;
    };
  };

  fileSystems."/var/lib/shoko" = {
    device = "zroot/services/shoko";
    fsType = "zfs";
    options = [ "nofail" ]; # Prevents boot hang if the pool is exported
  };

  systemd.services.shoko-perms = {
    description = "Set permissions for Shoko ZFS mount";
    after = [ "var-lib-shoko.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/chown -R 1000:${toString mediaGroupGid} /var/lib/shoko";
    };
  };

  networking.firewall.allowedTCPPorts = [ 8111 ];
}
