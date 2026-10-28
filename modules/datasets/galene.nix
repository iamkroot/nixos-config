{ ... }:
{
  "services/galene" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/galene";
    options = {
      mountpoint = "legacy";
      quota = "20G";
      recordsize = "128K";
      "sanoid:autosnap" = "true";
    };
  };
}
