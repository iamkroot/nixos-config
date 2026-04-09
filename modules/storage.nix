{
  config,
  pii,
  pkgs,
  ...
}:
let
  disk1 = pii.storage.disk1;
  media_main = pii.storage.media_main;
  media_bak = pii.storage.media_bak;
in
{
  vaultix.secrets."${disk1.name}-luks-key" = {
    file = disk1.luks-key;
    owner = "root";
    group = "root";
  };

  environment.etc.crypttab.text =
    let
      disk1-key = config.vaultix.secrets."${disk1.name}-luks-key".path;
    in
    ''
      # <target name>  <source device>       <key file>    <options>
      ${disk1.name}     UUID=${disk1.uuid}   ${disk1-key}  nofail,x-systemd.device-timeout=5s
    '';
  fileSystems."/mnt/${disk1.name}" = {
    device = "/dev/mapper/${disk1.name}";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.automount"
    ];
  };

  # something for local media
  systemd.tmpfiles.rules = [
    # 1. Create the directory if it doesn't exist
    "d /media 0775 root media - -"

    # 2. Apply ACLs to the directory itself (Access ACL)
    "A /media - - - - group:media:rwx"

    # 3. Ensure all NEW files/folders inherit these (Default ACL)
    "A /media - - - - default:group:media:rwx"

    # 4. (Optional) Fix existing files if you just migrated
    "Z /media 0775 root media - -"
  ];
  vaultix.secrets."${media_main.name}-zfs-key" = {
    file = media_main.key;
    owner = "root";
    group = "root";
  };
  vaultix.secrets."${media_bak.name}-zfs-key" = {
    file = media_bak.key;
    owner = "root";
    group = "root";
  };

  services.syncoid = {
    enable = true;

    # Run at 8AM daily
    interval = "*-*-* 08:00:00";

    # Define the replication task
    commands."media-backup" = {
      source = "${media_main.name}/media";
      target = "${media_bak.name}/media";
    };
  };

  systemd.services."syncoid-media-backup" = {
    # Give the pre/post scripts access to ZFS and hdparm commands
    path = with pkgs; [
      zfs
      hdparm
    ];

    # 0. Check if the media changed at all.
    serviceConfig.ExecCondition = pkgs.writeShellScript "check-zfs-changes" ''
      # 1. Find the newest snapshot on the primary dataset
      LATEST_SNAP=$(zfs list -t snapshot -H -o name -S creation -d 1 ${media_main.name}/media | head -n 1)

      # If no snapshots exist at all yet, we definitely need to run the backup
      if [ -z "$LATEST_SNAP" ]; then
        exit 0
      fi

      # 2. Extract just the snapshot name (the part after the '@')
      SNAP_NAME=''${LATEST_SNAP#*@}

      # 3. Ask ZFS exactly how many bytes have been written since that snapshot
      WRITTEN=$(zfs get -H -p -o value "written@$SNAP_NAME" ${media_main.name}/media)

      # 4. If exactly 0 bytes were written, abort the service.
      if [ "$WRITTEN" -eq 0 ]; then
        echo "0 bytes written since last snapshot. Letting the backup drive sleep."
        exit 1
      fi

      # Otherwise, changes were found! Proceed to wake the drive.
      exit 0
    '';

    # 1. BEFORE Syncoid runs: Wake up and import the pool
    preStart = ''
      # Check if the pool is already imported. If not, import it.
      # ZFS will automatically wake the drive up when it probes the disk.
      zpool status ${media_bak.name} >/dev/null 2>&1 || zpool import ${media_bak.name}
    '';

    # 2. AFTER Syncoid finishes: Export the pool and force sleep
    # (postStop runs whether the backup succeeded or failed, ensuring it never stays awake)
    postStop = ''
      # Export the pool to stop ZFS from doing background writes
      zpool export ${media_bak.name} || true

      # Send the sleep command to the drive. 
      hdparm -Y /dev/disk/by-id/${media_bak.id} || true
    '';
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
