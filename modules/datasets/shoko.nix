{ ... }:
{
  "services/shoko" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/shoko";
    options = {
      mountpoint = "legacy";
      quota = "50G";
      recordsize = "16K";
      "sanoid:autosnap" = "true";
    };
  };
}
