{ ... }:
{
  "services/nats" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/nats";
    options = {
      mountpoint = "legacy";
      quota = "30G";
      recordsize = "64K";
      "sanoid:autosnap" = "true";
    };
  };
}
