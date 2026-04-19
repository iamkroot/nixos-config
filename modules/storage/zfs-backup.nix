{
  config,
  pii,
  pkgs,
  lib,
  ...
}:
let
  primary_pool = pii.storage.media_main;
  secondary_pool = pii.storage.media_bak;

  # Define all the datasets we want backed up here
  targetDatasets = {
    "data" = {
      recursive = true;
    };
    "media" = { };
    "backup-homelab" = { recursive = true; };
    # "images" = { };
  };

  sanoidDASDatasets = lib.mapAttrs' (name: conf: {
    name = "${primary_pool.name}/${name}";
    value = {
      useTemplate = [ "defaultDASPolicy" ];
    }
    // conf;
  }) targetDatasets;

  sanoidTemplateOverrides = { };

  allZrootDatasets = lib.mapAttrsToList (
    name: ds:
    let
      path = if name == "__root" then "zroot" else "zroot/${name}";

      # Check explicit "false" to exclude. Leaves missing options as `null` to
      # prevent forced overwriting of native ZFS inheritance states.
      autoSnap = (ds.options or {})."sanoid:autosnap" 
              or (ds.options or {})."com.sun:auto-snapshot" 
              or null;

      # Check against Nix booleans AND common ZFS string values
      isIncluded = !(builtins.elem autoSnap [ false "false" "no" "off" ]);
      template = sanoidTemplateOverrides.${path} or "defaultDASPolicy";
    in
    {
      inherit path isIncluded template;
    }
  ) (config.disko.devices.zpool.zroot.datasets or { });

  syncoidExclusions = map (ds: "--exclude-datasets=^${ds.path}$") (
    lib.filter (ds: !ds.isIncluded) allZrootDatasets
  );

  # Build Sanoid Inclusions
  sanoidZrootDatasets = builtins.listToAttrs (
    map (ds: {
      name = ds.path;
      value = {
        useTemplate = [ ds.template ];
      };
    }) (lib.filter (ds: ds.isIncluded) allZrootDatasets)
  );
in
{
  # Dynamically generate Sanoid snapshot policies for all target datasets
  services.sanoid = {
    enable = true;
    templates = {
      defaultDASPolicy = {
        autosnap = true;
        autoprune = true;
        hourly = 0;
        daily = 7;
        weekly = 4;
        monthly = 3;
        yearly = 0;
      };
      hourly = {
        hourly = 24;
        daily = 7;
        monthly = 3;
        autoprune = true;
        autosnap = true;
      };
      storage = {
        daily = 7;
        monthly = 1;
        autoprune = true;
        autosnap = true;
      };
    };

    datasets = sanoidDASDatasets // sanoidZrootDatasets;
  };

  services.syncoid = {
    enable = true;
    interval = "*-*-* 07:30:00";
    commands."backup-zroot" = {
      source = "zroot";
      target = "${primary_pool.name}/backup-homelab";
      recursive = true;
      extraArgs = [ "--sendoptions=w" ] ++ syncoidExclusions;
    };
  };

  systemd.services."syncoid-backup-zroot".serviceConfig = { 
    # Keep root to bypass NixOS's messy ZFS delegation logic
    User = lib.mkForce "root";
    Group = lib.mkForce "root";
    
    # 1. Device Protection
    # Turn PrivateDevices ON, but explicitly whitelist the ZFS device node.
    PrivateDevices = lib.mkForce true;
    DeviceAllow = lib.mkForce [ "/dev/zfs rw" ];
    BindPaths = lib.mkForce [ "/dev/zfs" ];
    
    # 2. Filesystem Protection
    # 'full' mounts /usr, /boot, and /etc as read-only. 
    # (Do not use 'strict', because ZFS needs to be able to create dataset mountpoints dynamically)
    ProtectSystem = lib.mkForce "full";
    
    # Block access to user directories since this is a local-to-local sync
    ProtectHome = lib.mkForce true;
    
    # 3. Capability Bounding
    # Give ZFS exactly the capabilities it needs, rather than "~" (everything).
    # SYS_ADMIN is required for dataset management/mounting.
    # DAC/FOWNER bypasses file ownership locks during the replication process.
    CapabilityBoundingSet = lib.mkForce [ 
      "CAP_SYS_ADMIN" 
      "CAP_DAC_OVERRIDE" 
      "CAP_DAC_READ_SEARCH" 
      "CAP_FOWNER" 
      "CAP_CHOWN"         # Required when receiving a stream that restores file ownership
      "CAP_FSETID"        # Required when receiving a stream that restores setuid/setgid bits
      "CAP_SYS_RESOURCE"  # ZFS userland utilities often adjust their own wait-states/OOM limits
      "CAP_SYS_MODULE"    # Prevents libzfs from crashing if it ever decides it needs to verify the kernel module
    ];
  };

  # Define a unified timer directly instead of using syncoid module
  systemd.timers."zfs-backup-das" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 08:00:00";
      Persistent = true;
    };
  };

  # The Unified Backup Service
  systemd.services."zfs-backup-das" = {
    description = "Sequential ZFS Backup to Secondary Pool";
    path = with pkgs; [
      zfs
      sanoid
      zfs-prune-snapshots
      hdparm
      coreutils
    ];

    after = [ "sanoid.service" ];
    wants = [ "sanoid.service" ];

    # Inject Nix variables into the bash environment
    environment = {
      ZFS_BIN = "${pkgs.zfs}/bin/zfs";
      SYNCOID_BIN = "${pkgs.sanoid}/bin/syncoid";
      PRUNE_BIN = "${pkgs.zfs-prune-snapshots}/bin/zfs-prune-snapshots";
      PRIMARY_POOL = primary_pool.name;
      SECONDARY_POOL = secondary_pool.name;
      TARGET_DATASETS = builtins.concatStringsSep " " (builtins.attrNames targetDatasets);
      # silence mbuffer error
      HOME = "/var/empty";
    };

    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "zfs-backup";

      ExecCondition = "+${pkgs.writeShellScript "check-any-sync-needed" (builtins.readFile ./zfs-check-sync-das.sh)}";

      ExecStartPre = "+${pkgs.writeShellScript "import-pool" ''
        zpool status ${secondary_pool.name} >/dev/null 2>&1 || zpool import ${secondary_pool.name}
      ''}";

      ExecStart = "+${pkgs.writeShellScript "run-backups" (builtins.readFile ./zfs-backup-das.sh)}";

      ExecStopPost = "+${pkgs.writeShellScript "export-and-sleep" ''
        DEVICES=$(${pkgs.zfs}/bin/zpool list -v -H -P ${secondary_pool.name} | ${pkgs.gawk}/bin/awk '{print $1}' | ${pkgs.gnugrep}/bin/grep '^/')

        sleep 2

        ${pkgs.zfs}/bin/zpool export ${secondary_pool.name} || true

        for dev in $DEVICES; do
          PKNAME=$(${pkgs.util-linux}/bin/lsblk -no pkname "$dev")
          if [ -n "$PKNAME" ]; then
            PARENT_DEV="/dev/$PKNAME"
          else
            PARENT_DEV="$dev" # Fallback if it's already a whole disk
          fi
          ${pkgs.smartmontools}/bin/smartctl -A "$PARENT_DEV" | ${pkgs.gnugrep}/bin/grep Start_Stop_Count
          ${pkgs.hdparm}/bin/hdparm -Y "$PARENT_DEV" || true
        done
      ''}";
    };
  };

  services.smartd = {
    enable = true;
    # '-n standby,q' ensures it skips asleep drives quietly
    defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03)";
  };

  # Tell udisks2 to completely ignore the backup drive so it doesn't wake it
  services.udev.extraRules = ''
    ENV{ID_SERIAL}=="${secondary_pool.serial}", ENV{UDISKS_IGNORE}="1"
  '';
}
