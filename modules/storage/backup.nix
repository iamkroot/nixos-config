{
  config,
  pii,
  pkgs,
  ...
}:
let
  media_main = pii.storage.media_main;
  media_bak = pii.storage.media_bak;
  data_main = pii.storage.data_main;
  data_bak = pii.storage.data_bak;
in
{
  services.sanoid = {
    enable = true;
    datasets."${media_main.name}/media" = {
      autosnap = true;
      autoprune = true;
      hourly = 0;
      daily = 7;
      weekly = 4;
      monthly = 3;
      yearly = 0;
    };
  };

  services.syncoid = {
    enable = true;
    interval = "*-*-* 08:00:00";
    commonArgs = [ "--no-sync-snap" ];
    commands."media-backup" = {
      source = "${media_main.name}/media";
      target = "${media_bak.name}/media";
      recvOptions = "o canmount=noauto";
    };
  };

  systemd.services."media-backup-hardware" = {
    description = "Manage backup pool hardware state";
    path = with pkgs; [
      zfs
      hdparm
      coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStart = pkgs.writeShellScript "import-pool" ''
        zpool status ${media_bak.name} >/dev/null 2>&1 || zpool import ${media_bak.name}
      '';

      ExecStop = pkgs.writeShellScript "export-and-sleep" ''
        # Optional: brief sleep to let lingering IO finish before export
        sleep 2 
        zpool export -f ${media_bak.name} || true
        hdparm -Y /dev/disk/by-id/${media_bak.id} || true
      '';
    };
  };
  systemd.services."syncoid-media-backup" = {
    path = with pkgs; [
      zfs
      systemd
      zfs-prune-snapshots
    ];

    after = [ "sanoid.service" ];
    wants = [ "sanoid.service" ];

    serviceConfig = {
      # Tells systemd to create and manage /var/lib/media-backup/ for persistent state
      StateDirectory = "media-backup";

      ExecCondition = "+${pkgs.writeShellScript "check-zfs-changes" ''
        LATEST_SNAP=$(${pkgs.zfs}/bin/zfs list -t snapshot -H -o name -S creation -d 1 ${media_main.name}/media | head -n 1)
        if [ -z "$LATEST_SNAP" ]; then exit 0; fi

        STATE_FILE="/var/lib/media-backup/last_synced_snap"

        # 1. Did we ALREADY sync this exact snapshot?
        if [ -f "$STATE_FILE" ]; then
          if [ "$LATEST_SNAP" == "$(cat "$STATE_FILE")" ]; then
            echo "Snapshot $LATEST_SNAP already synced. Keeping drive asleep."
            exit 1
          fi
        fi

        # 2. Is this a completely empty snapshot?
        WRITTEN=$(${pkgs.zfs}/bin/zfs get -H -p -o value written "$LATEST_SNAP")
        if [ "$WRITTEN" -eq 0 ]; then
          echo "0 bytes written since previous snapshot. Keeping drive asleep."
          exit 1
        fi

        exit 0
      ''}";

      ExecStartPre = "+${pkgs.systemd}/bin/systemctl start media-backup-hardware.service";

      # ExecStartPost only triggers if Syncoid finishes with a "Success" exit code
      ExecStartPost = [
        # 1. Save the newly synced snapshot name so we remember it tomorrow
        "+${pkgs.writeShellScript "save-sync-state" ''
          ${pkgs.zfs}/bin/zfs list -t snapshot -H -o name -S creation -d 1 ${media_main.name}/media | head -n 1 > /var/lib/media-backup/last_synced_snap
        ''}"

        # 2. Run the prune
        "+${pkgs.writeShellScript "prune-backup-snapshots" ''
          if ${pkgs.zfs}/bin/zfs list ${media_bak.name}/media >/dev/null 2>&1; then
            echo "Cleaning up backup snapshots older than 6 months..."
            ${pkgs.zfs-prune-snapshots}/bin/zfs-prune-snapshots -p 'autosnap_' 6M ${media_bak.name}/media || true
          else
            echo "Target dataset does not exist yet. Skipping prune."
          fi
        ''}"
      ];

      ExecStopPost = "+${pkgs.systemd}/bin/systemctl stop media-backup-hardware.service";
    };
  };

  services.smartd = {
    enable = true;
    # '-n standby,q' ensures it skips asleep drives quietly
    defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03)";
  };

  # Tell udisks2 to completely ignore the backup drive so it doesn't wake it
  services.udev.extraRules = ''
    ENV{ID_SERIAL}=="${media_bak.serial}", ENV{UDISKS_IGNORE}="1"
  '';
}
