{ ... }:
{
  "services/mindwtr" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/mindwtr";
    options = {
      mountpoint = "legacy";
      quota = "10G";
      recordsize = "128K";
      "sanoid:autosnap" = "true";
    };
  };
}
