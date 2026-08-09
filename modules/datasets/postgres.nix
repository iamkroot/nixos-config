{ ... }:
{
  "services/postgres" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/postgresql";
    options = {
      mountpoint = "legacy";
      # Matches PostgreSQL native 8KB page size to eliminate write amplification
      recordsize = "8K";
      xattr = "sa";
      atime = "off";
      quota = "50G";
      "sanoid:autosnap" = "true";
    };
  };
}
