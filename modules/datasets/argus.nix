{ ... }:
{
  "services/argus" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/argus";
    options = {
      mountpoint = "legacy";
      quota = "1G";
      recordsize = "16K";
      "sanoid:autosnap" = "true";
    };
  };
}
