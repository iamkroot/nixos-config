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
    "images" = { };
  };

  # Define the base sanoid policy applied to everything
  defaultPolicy = {
    autosnap = true;
    autoprune = true;
    hourly = 0;
    daily = 7;
    weekly = 4;
    monthly = 3;
    yearly = 0;
  };
in
{
  # Dynamically generate Sanoid snapshot policies for all target datasets
  services.sanoid = {
    enable = true;
    datasets = lib.mapAttrs' (name: conf: {
      name = "${primary_pool.name}/${name}";
      value = defaultPolicy // conf;
    }) targetDatasets;
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
