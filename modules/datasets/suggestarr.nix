{ ... }:
{
  "services/suggestarr" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/suggestarr";
    options = {
      mountpoint = "legacy";
      quota = "5G";
      recordsize = "16K";
      "sanoid:autosnap" = "true";
    };
  };
}
