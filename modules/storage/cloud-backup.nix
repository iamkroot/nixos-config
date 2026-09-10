{
  config,
  lib,
  pkgs,
  pii,
  ...
}:
let
  zrootDatasets = config.disko.devices.zpool.zroot.datasets or { };

  # Determine if a dataset should be excluded from Kopia backup.
  # Checks explicit "kopia:backup", falling back to "syncoid:sync" or "sanoid:autosnap".
  isDatasetIgnored =
    ds:
    let
      kopiaOpt = (ds.options or { })."kopia:backup" or null;
      syncoidOpt = (ds.options or { })."syncoid:sync" or null;
      autoSnap = (ds.options or { })."sanoid:autosnap" or null;
    in
    kopiaOpt == "false"
    || (kopiaOpt == null && (syncoidOpt == "no" || syncoidOpt == "false" || autoSnap == "false"));

  # Helper: auto-generate ignore globs for any datasets mounted underneath a given root path.
  getDiskoIgnoresFor =
    rootPath:
    let
      prefix = lib.removeSuffix "/" rootPath + "/";
      ignoredMounts = lib.filterAttrs (
        _: ds:
        ds ? mountpoint
        && ds.mountpoint != null
        && (lib.hasPrefix prefix ds.mountpoint)
        && (isDatasetIgnored ds)
      ) zrootDatasets;
    in
    lib.mapAttrsToList (_: ds: "${lib.removePrefix prefix ds.mountpoint}/") ignoredMounts;

  globalIgnores = [
    "*.tmp"
    "*.temp"
    "*.swp"
    "*~"
    "cache/"
    ".cache/"
    "Trash/"
    ".Trash/"
    ".Trash-*/"
    "Thumbs.db"
    ".DS_Store"
    "lost+found/"
    "*.log"
    "*.bak"
  ];

  # TODO: Should add a task/routine to regularly update these lists
  varLibIgnores =
    globalIgnores
    ++ (getDiskoIgnoresFor "/var/lib")
    ++ [
      # Self-referential & system state
      "kopia/"
      "systemd/"
      "machines/"
      "portables/"
      "cni/"
      "fwupd/"
      "lastlog"
      "zfs-backup/"
      "media-backup/"

      # Application caches, internal backups, and artwork
      "jellyfin/data/backups/"
      "shoko/Shoko.CLI/images/"
      "shoko/Shoko.CLI/Anime_HTTP/"
      "vaultwarden/icon_cache/"
      "vaultwarden/tmp/"
      "homeassistant/tts/"
      "crowdsec/data/*.mmdb"
      "profilarr/backups/"

      # *arr caches, internal backups, and SQLite logs
      "MediaCover/"
      "Backups/"
      "logs.db*"
      "logs/"
      "log/"
    ];

  homeIgnores =
    globalIgnores
    ++ (getDiskoIgnoresFor "/home")
    ++ [
      "*/.local/share/Trash/"
      "*/.local/share/flatpak/"
      # Steam runtime binaries and client update packages (preserving userdata and configs)
      "*/.local/share/Steam/package/"
      "*/.local/share/Steam/ubuntu12_32/"
      "*/.local/share/Steam/ubuntu12_64/"
      "*/.local/share/Steam/steamrt32/"
      "*/.local/share/Steam/steamrt64/"
      "*/.local/share/Steam/steamui/"
      "*/.local/share/Steam/appcache/"
      "*/.local/share/Steam/depotcache/"
    ];
in
{
  vaultix.secrets = {
    "cloud1-storage-key".file = pii.kopia.cloud1StorageKey;
    "kopia-password".file = pii.kopia.password;
  };

  services.kopia.backups.azure-cloud = {
    user = "root";
    passwordFile = config.vaultix.secrets."kopia-password".path;

    # Azure Blob Storage backend
    repository.azure = {
      storageAccount = pii.kopia.storageAccount;
      container = pii.kopia.container;
      storageKeyFile = config.vaultix.secrets."cloud1-storage-key".path;
    };

    # Global policy tuned for cool tier
    policies.entries."(global)" = {
      compression.compressorName = "zstd";
      retention = {
        keepLatest = 7;
        keepDaily = 30; # >= 30 days avoids early deletion penalty fees
        keepWeekly = 8;
        keepMonthly = 6;
        keepAnnual = 1;
      };
      files = {
        # Note: oneFileSystem is true globally as safety against accidental filesystem traversal.
        # We explicitly set oneFileSystem = false on snapshots where we want to cross child dataset mounts.
        oneFileSystem = true;
        ignoreCacheDirs = true;
        ignore = globalIgnores;
      };
    };

    snapshots = {
      # User home directories (excluding Steam game installs, shadercaches, launcher downloads via Disko)
      home = {
        path = "/home";
        policy.files = {
          oneFileSystem = false; # Allow traversing into /home/kroot and included child datasets (userdata, compatdata)
          ignore = homeIgnores;
        };
        timer = {
          enable = true;
          options = {
            OnCalendar = "*-*-* 01:00:00";
            Persistent = true;
          };
        };
      };

      # Services data on zroot (excluding ephemeral datasets like containers, trickplay, caches derived from Disko)
      services-var-lib = {
        path = "/var/lib";
        policy.files = {
          oneFileSystem = false; # Allow traversing into /var/lib/postgresql, jellyfin, etc.
          ignore = varLibIgnores;
        };
        timer = {
          enable = true;
          options = {
            OnCalendar = "*-*-* 02:00:00";
            Persistent = true;
          };
        };
      };

      # Media SSD critical data (excluding media video files and downloads)
      media = {
        path = "/media";
        policy.files = {
          oneFileSystem = false; # Allow traversing into sub-datasets
          # TODO: Handle these via disko-like properties too
          ignore = globalIgnores ++ [
            "Animu/"
            "Movies/"
            "TV/"
            "Unwatched/"
            "Downloads/"
            ".Trash-1000/"
            "Music/"
            "photos/encoded-video/"
            "photos/thumbs/"
          ];
        };
        extraServiceConfig = {
          ExecCondition = "${pkgs.util-linux}/bin/mountpoint -q /media";
        };
        timer = {
          enable = true;
          options = {
            OnCalendar = "*-*-* 03:00:00";
            Persistent = true;
          };
        };
      };

      data-main = {
        path = pii.storage.data_main.mountpoint;
        policy.files = {
          oneFileSystem = false; # Traverse across child datasets
        };
        extraServiceConfig = {
          ExecCondition = "${pkgs.util-linux}/bin/mountpoint -q ${pii.storage.data_main.mountpoint}";
        };
        timer = {
          enable = true;
          options = {
            OnCalendar = "*-*-* 04:00:00";
            Persistent = true;
          };
        };
      };
    };
  };
}
