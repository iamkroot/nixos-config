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
}
