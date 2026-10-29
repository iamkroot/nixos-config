{ ... }:
{
  "services/nitter" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/nitter";
    options = {
      mountpoint = "legacy";
      quota = "10G";
      recordsize = "64K";
      "sanoid:autosnap" = "true";
    };
  };
}
