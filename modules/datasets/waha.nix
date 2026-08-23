{ ... }:
{
  "services/waha" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/waha";
    options = {
      mountpoint = "legacy";
      quota = "20G";
      recordsize = "128K";
      "sanoid:autosnap" = "true";
    };
  };
}
