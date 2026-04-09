{ ... }:
{
  "services/authelia" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/authelia";
    options = {
      mountpoint = "legacy";
      quota = "50G";
      recordsize = "16K";
      "com.sun:auto-snapshot" = "true";
    };
  };
}
