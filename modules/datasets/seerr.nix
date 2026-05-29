{ ... }:
{
  "services/seerr" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/seerr";
    options = {
      mountpoint = "legacy";
      quota = "10G";
      recordsize = "16K";
      "sanoid:autosnap" = "true";
    };
  };
  "services/seerr/logs" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/seerr/logs";
    options = {
      mountpoint = "legacy";
      refquota = "5G";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
    };
  };
  "services/seerr/db" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/seerr/db";
    options = {
      mountpoint = "legacy";
      recordsize = "16K";
      primarycache = "all";
    };
  };
  "services/seerr/cache" = {
    mountpoint = "/var/lib/seerr/cache";
    type = "zfs_fs";
    options = {
      mountpoint = "legacy";
      recordsize = "1M";
      sync = "disabled"; # don't care about consistency
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
    };
  };
}
