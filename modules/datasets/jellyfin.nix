{ ... }:
{
  "services/jellyfin" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/jellyfin";
    options = {
      mountpoint = "legacy";
      quota = "100G";
      recordsize = "16K";
      "sanoid:autosnap" = "true";
    };
  };
  "services/jellyfin/data/trickplay" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/jellyfin/data/trickplay";
    options = {
      mountpoint = "legacy";
      refquota = "50G";
      recordsize = "1M";
      compression = "off";
      "sanoid:autosnap" = "false";
    };
  };
  "services/jellyfin/data/subtitles" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/jellyfin/data/subtitles";
    options = {
      mountpoint = "legacy";
      refquota = "10G";
      recordsize = "1M";
      "sanoid:autosnap" = "false";
    };
  };
  "services/jellyfin/cache" = {
    mountpoint = "/var/cache/jellyfin";
    type = "zfs_fs";
    options = {
      mountpoint = "legacy";
      compression = "off";
      recordsize = "1M";
      sync = "disabled"; # don't care about consistency
      "sanoid:autosnap" = "false";
    };
  };
}
