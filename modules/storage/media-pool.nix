{
  config,
  pkgs,
  lib,
  pii,
  ...
}:

let
  media_main = pii.storage.media_main;
  data_main = pii.storage.data_main;
  poolName = media_main.name;
  mediaMount = "mnt-${poolName}-media.mount";
  mediaServiceAttrs = {
    bindsTo = [
      "media-apps.target"
      mediaMount
    ];
    after = [
      "media-apps.target"
      mediaMount
      "load-${poolName}-keys.service"
    ];
    wantedBy = [ "media-apps.target" ];
  };
in
{
  vaultix.secrets."${poolName}-zfs-key" = {
    file = media_main.key;
    owner = "root";
    group = "root";
  };

  vaultix.secrets."${data_main.name}-data-zfs-key" = {
    file = data_main.key;
    owner = "root";
    group = "root";
  };

  boot.zfs.extraPools = [ poolName ];

  # This service dynamically hooks into every mount unit generated above.
  systemd.services."load-${poolName}-keys" = {
    description = "Load encryption keys for all datasets on ${poolName}";
    unitConfig.DefaultDependencies = false;
    requires = [ "zfs-import-${poolName}.service" ];
    after = [ "zfs-import-${poolName}.service" ];

    # This ensures it runs BEFORE systemd attempts to mount local filesystems
    before = [
      # "zfs-mount.service"
      "local-fs.target"
    ];
    # Trigger this service as part of the ZFS import target
    wantedBy = [ "zfs-import-${poolName}.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.zfs}/bin/zfs load-key -r ${poolName} || true'";
    };
  };

  # This listens for any block device being added that is formatted
  # as a ZFS member and belongs to the "castor" pool.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="zfs_member", ENV{ID_FS_LABEL}=="${poolName}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="${poolName}-automount.service"
  '';

  # Auto mount on hotplug
  systemd.services."${poolName}-automount" = {
    description = "Automount ${poolName} DAS and start media apps";

    # We don't want this starting during normal boot, ONLY when triggered by udev
    unitConfig = {
      DefaultDependencies = false;
    };

    serviceConfig = {
      Type = "oneshot";
      # Prevents udev from spamming the script if multiple disks connect at once
      RemainAfterExit = true;
    };

    path = with pkgs; [
      zfs
      systemd
      coreutils
    ];

    script = ''
      sleep 5
      zpool import -l ${poolName} || true

      systemctl daemon-reload
      systemctl start media-apps.target
    '';
  };
  systemd.targets.media-apps = {
    description = "Target for all media-related services tied to the DAS";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.jellyfin = lib.mkIf config.services.jellyfin.enable mediaServiceAttrs;

  systemd.services.podman-shoko-server = lib.mkIf (builtins.hasAttr "shoko-server" config.virtualisation.oci-containers.containers) mediaServiceAttrs;
}
