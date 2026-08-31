{ pii, ... }:
{
  "media/dav" = {
    type = "zfs_fs";
    mountpoint = pii.davDir;
    mountOptions = [
      "x-systemd.requires-mounts-for=/media"
    ];
    options = {
      mountpoint = "legacy";
      quota = "100G";
      recordsize = "128K";
      "sanoid:autosnap" = "true";
    };
  };
}
