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
  data_main = pii.storage.data_main;
  data_bak = pii.storage.data_bak;
  # util
  mkZfsAutomount =
    {
      poolName,
      datasetName,
      secretName,
      uuid,
    }:
    let
      escapedUuid = builtins.replaceStrings [ "-" ] [ "\\x2d" ] uuid;
      deviceUnit = "dev-disk-by\\x2duuid-${escapedUuid}.device";

      # Converts "datapool/data" to "datapool-data" to create a safe, unique systemd name
      datasetSlug = builtins.replaceStrings [ "/" ] [ "-" ] datasetName;
    in
    {

      # Mount to /mnt/datapool/data instead of just /mnt/datapool
      fileSystems."/mnt/${datasetName}" = {
        device = datasetName;
        fsType = "zfs";
        options = [
          "nofail"
          "x-systemd.automount"
          "x-systemd.requires=zfs-unlock-${datasetSlug}.service"
        ];
      };

      systemd.services."zfs-unlock-${datasetSlug}" = {
        description = "Unlock ZFS dataset ${datasetName}";
        bindsTo = [ deviceUnit ];
        after = [ deviceUnit ];
        before = [ "mnt-${datasetSlug}.mount" ];
        path = [ pkgs.zfs ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;

          # Try to import the pool. The '-' prefix ensures that if the pool is
          # already imported by another dataset, systemd ignores the error and continues.
          ExecStartPre = "-${pkgs.zfs}/bin/zpool import -N ${poolName}";
          # Finds all nested datasets under this specific parent and mounts them individually
          ExecStartPost =
            let
              # We use absolute paths to packages to ensure systemd can find them
              zfs = "${pkgs.zfs}/bin/zfs";
              grep = "${pkgs.gnugrep}/bin/grep";
              xargs = "${pkgs.findutils}/bin/xargs";
              bash = "${pkgs.bash}/bin/bash";
            in
            "${bash} -c '${zfs} list -r -H -o name -t filesystem ${datasetName} | ${grep} \"^${datasetName}/\" | ${xargs} -r -I{} ${zfs} mount {}'";

          # Load the key for this specific dataset
          ExecStart = "${pkgs.zfs}/bin/zfs load-key -L file://${
            config.vaultix.secrets."${secretName}".path
          } ${datasetName}";

          # When unmounted, ONLY unload this dataset's key. Do not export the whole pool!
          # The '-' prefix ignores errors just in case the key is already unloaded.
          ExecStop = "-${pkgs.zfs}/bin/zfs unload-key ${datasetName}";
        };
      };
    };
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

  vaultix.secrets."${data_main.name}-data-zfs-key" = {
    file = data_main.key;
    owner = "root";
    group = "root";
  };

  # couldn't get automount working reliably
  imports = [
    # (mkZfsAutomount {
    #   poolName = media_main.name;
    #   datasetName = "${media_main.name}/media";
    #   secretName = "${media_main.name}-zfs-key";
    #   uuid = media_main.uuid;
    # })
    # (mkZfsAutomount {
    #   poolName = data_main.name;
    #   datasetName = "${data_main.name}/data";
    #   secretName = "${data_main.name}-data-zfs-key";
    #   uuid = data_main.uuid;
    # })
  ];
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
