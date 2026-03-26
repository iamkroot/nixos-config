{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };
    zpool = {
      zroot = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          relatime = "on";
          dnodesize = "auto";
          canmount = "off";
          devices = "off";

          encryption = "on";
          keyformat = "passphrase";
          keylocation = "file:///tmp/zfs-secret.key";
        };
        postCreateHook = "zfs set keylocation=prompt zroot";

        datasets = {
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
            options.reservation = "1G";
          };
          "home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.atime = "off";
            options.mountpoint = "legacy";
          };
          "swap" = {
            type = "zfs_volume";
            size = "16G"; # Set this to your desired swap size
            content = {
              type = "swap";
              randomEncryption = true; # Highly recommended for SSD health + security
            };
            options = {
              "com.sun:auto-snapshot" = "false";
              # Critical performance tweaks for ZVOL swap:
              volblocksize = "4K"; # Matches page size
              sync = "disabled"; # Safe for swap; improves speed
              compression = "off"; # Swapping compressed data is redundant CPU waste
              logbias = "throughput";
            };
          };
          "jellyfin_data" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/jellyfin";
            options = {
              mountpoint = "legacy";
              quota = "50G";
              recordsize = "16K";
            };
          };
        };
      };
    };
  };
}
