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
    # Bind to the target so the app dies if the drive is exported
    bindsTo = [ "media-apps.target" ];    
    after = [ "load-${poolName}-keys.service" ];
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

  # This listens for any block device being added that is formatted
  # as a ZFS member and belongs to the "poolName" pool.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="zfs_member", ENV{ID_FS_LABEL}=="${poolName}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="load-${poolName}-keys.service"
  '';

  # Override the native NixOS import service to handle safe exports
  systemd.services."zfs-import-${poolName}" = {
    serviceConfig = {
      # The minus sign (-) ignores the error if the pool is already gone
      ExecStop = "-${pkgs.zfs}/bin/zpool export ${poolName}";
    };
  };

  # Key loading and mounting (Self-contained)
  systemd.services."load-${poolName}-keys" = {
    description = "Load encryption keys and mount datasets for ${poolName}";
    unitConfig.DefaultDependencies = false;

    requires = [ "zfs-import-${poolName}.service" ];
    after = [ "zfs-import-${poolName}.service" ];

    # BindsTo ensures that if the import service stops, this state resets too
    bindsTo = [ "zfs-import-${poolName}.service" ];
    before = [ "local-fs.target" ];
    # Auto start the media apps
    wants = [ "media-apps.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "load-zfs-keys-and-mount" ''
        ${pkgs.zfs}/bin/zfs get -H -o name,value keylocation -r "${poolName}" | \
        while IFS=$'\t' read -r name value; do
          if [[ "$value" == file://* ]]; then
            # Check if the key is actually needed
            keystatus=$(${pkgs.zfs}/bin/zfs get -H -o value keystatus "$name")
            
            if [ "$keystatus" = "unavailable" ]; then
              echo "Loading key for $name from $value..."
              ${pkgs.zfs}/bin/zfs load-key "$name" || true
            else
              echo "Key for $name is already loaded. Skipping..."
            fi
          fi
        done

        # Mount the datasets natively
        ${pkgs.zfs}/bin/zfs mount -a || true
      '';
    };
  };

  systemd.targets.media-apps = {
    description = "Target for all media-related services tied to the DAS";
    # BindsTo means: If load-keys stops (drive exported), drop this target.
    # After means: Do not let apps start until load-keys has successfully finished mounting.
    bindsTo = [ "load-${poolName}-keys.service" ];
    after = [ "load-${poolName}-keys.service" ];
  };

  systemd.services.jellyfin = lib.mkIf config.services.jellyfin.enable mediaServiceAttrs;

  systemd.services.podman-shoko-server = lib.mkIf (builtins.hasAttr "shoko-server" config.virtualisation.oci-containers.containers) mediaServiceAttrs;
}
