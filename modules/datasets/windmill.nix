{ ... }:
{
  # Parent dataset for organization (does not mount anywhere)
  "services/windmill" = {
    type = "zfs_fs";
    options = {
      mountpoint = "none";
    };
  };

  # 1. PostgreSQL Database
  "services/windmill/postgres" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/windmill/postgres";
    options = {
      mountpoint = "legacy";
      # Matches PostgreSQL native 8KB page size to eliminate write amplification
      recordsize = "8K";
      xattr = "sa";
      atime = "off";
      logbias = "throughput";
      quota = "50G";
      "sanoid:autosnap" = "true";
    };
  };

  # 2. Worker Dependency Cache (pip, npm, deno, bun)
  "services/windmill/cache" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/windmill/cache";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      atime = "off";
      quota = "30G";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
      "kopia:backup" = "false";
    };
  };

  # 3. Execution Logs
  "services/windmill/logs" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/windmill/logs";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      atime = "off";
      quota = "20G";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
      "kopia:backup" = "false";
    };
  };

  # 4. LSP Symbol Cache
  "services/windmill/lsp-cache" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/windmill/lsp-cache";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      atime = "off";
      quota = "10G";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
      "kopia:backup" = "false";
    };
  };
}
