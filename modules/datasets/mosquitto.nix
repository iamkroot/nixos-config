{ ... }:
{
  "services/mosquitto" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/mosquitto";
    options = {
      mountpoint = "legacy";
      quota = "10G";
      recordsize = "64K";
      "sanoid:autosnap" = "true";
    };
  };
}
