{ ... }:
{
  "services/adguard" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/private/AdGuardHome";
    options = {
      mountpoint = "legacy";
      quota = "10G";
      recordsize = "64K";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
      "kopia:backup" = "false";
    };
  };
}
