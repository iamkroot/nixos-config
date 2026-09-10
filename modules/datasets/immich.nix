{ ... }:
{
  # Parent dataset for organization (does not mount anywhere)
  "services/immich" = {
    type = "zfs_fs";
    options = {
      mountpoint = "none";
    };
  };

  # 1. PostgreSQL Database Data
  "services/immich/postgres" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/immich/postgres";
    options = {
      mountpoint = "legacy";
      # CRITICAL: 16K matches Postgres page size to prevent massive write amplification
      recordsize = "16K";
      xattr = "sa";
      atime = "off";
      logbias = "throughput";
    };
  };

  # 2. Machine Learning Model Cache
  "services/immich/model-cache" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/immich/model-cache";
    options = {
      mountpoint = "legacy";
      recordsize = "128K"; # Standard recordsize is fine here
      atime = "off";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
    };
  };

  # 3. Fast Thumbnail Storage (Micro, Thumb, Preview)
  "services/immich/thumbs" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/immich/thumbs";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      quota = "100G";
      acltype = "posixacl";
      xattr = "sa";
      "kopia:backup" = "false";
    };
  };
}
