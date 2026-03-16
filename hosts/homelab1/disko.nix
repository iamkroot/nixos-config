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
        };
        rootFsOptions = {
          compression = "lz4";
          acltype = "posixacl";
          xattr = "sa";
          relatime = "on";
          dnodesize = "auto";
          normalization = "formD";
          canmount = "off";
          devices = "off";
          autotrim = "on";

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
          };
          "home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
