{
  pii,
  ...
}:
let
  user = pii.primaryUser;
in
{
  # Parent dataset for organization (does not mount directly)
  "gaming" = {
    type = "zfs_fs";
    options = {
      mountpoint = "none";
    };
  };

  "gaming/steam" = {
    type = "zfs_fs";
    options = {
      mountpoint = "none";
    };
  };

  # Steam Apps / Game Installations
  # Large continuous game assets/textures -> 1M recordsize for fast sequential read performance
  "gaming/steam/common" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/Steam/steamapps/common";
    options = {
      mountpoint = "legacy";
      recordsize = "1M";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
    };
  };

  # Steam Compatdata / Proton & Wine Prefixes
  "gaming/steam/compatdata" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/Steam/steamapps/compatdata";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      "sanoid:autosnap" = "true";
      "syncoid:sync" = "yes";
    };
  };

  # Steam Shader Cache (DXVK, VKD3D, Vulkan/OpenGL shader compilation cache)
  # High-churn ephemeral cache -> sync=disabled for max write performance
  "gaming/steam/shadercache" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/Steam/steamapps/shadercache";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      sync = "disabled";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
    };
  };

  # Steam Downloading Staging Area
  # Temporary files during game downloads
  "gaming/steam/downloading" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/Steam/steamapps/downloading";
    options = {
      mountpoint = "legacy";
      recordsize = "1M";
      sync = "disabled";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
    };
  };

  # Steam User Data (Local Game Saves, Screenshots, Cloud Sync, Controller Configs)
  # Critical user data -> autosnap enabled for snapshotting and backups
  "gaming/steam/userdata" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/Steam/userdata";
    options = {
      mountpoint = "legacy";
      recordsize = "16K";
      "sanoid:autosnap" = "true";
      "syncoid:sync" = "yes";
    };
  };

  # Heroic Games Launcher Data & Installed Games / Prefixes
  "gaming/heroic" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/heroic";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      "sanoid:autosnap" = "false";
    };
  };

  # Lutris Launcher Data, Runners & Wine Prefixes
  "gaming/lutris" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/lutris";
    options = {
      mountpoint = "legacy";
      recordsize = "64K";
      "sanoid:autosnap" = "false";
    };
  };

  "gaming/bottles" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/bottles";
    options = {
      mountpoint = "legacy";
      recordsize = "128K";
      "sanoid:autosnap" = "false";
    };
  };

  # Critical save backups -> autosnap enabled
  "gaming/ludusavi" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.local/share/ludusavi";
    options = {
      mountpoint = "legacy";
      recordsize = "16K";
      "sanoid:autosnap" = "true";
      "syncoid:sync" = "yes";
    };
  };

  # Default Wine Prefix (~/.wine)
  "gaming/wine" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.wine";
    options = {
      mountpoint = "legacy";
      recordsize = "16K";
      "sanoid:autosnap" = "false";
    };
  };

  # General Non-Steam Games & Emulation ROMs (~/Games)
  "gaming/games" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/Games";
    options = {
      mountpoint = "legacy";
      recordsize = "1M";
      "sanoid:autosnap" = "true";
    };
  };
}
