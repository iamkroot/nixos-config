{ ... }:
{
  "services/onstar2mqtt" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/onstar2mqtt";
    options = {
      mountpoint = "legacy";
      quota = "5G";
      recordsize = "128K";
      "sanoid:autosnap" = "true";
    };
  };
}
