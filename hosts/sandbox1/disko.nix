{ inputs, lib, ... }:
let
  serviceFiles = [
    (inputs.self + /modules/datasets/jellyfin.nix)
  ];

  customDatasets = lib.foldl' (acc: path: acc // (import path { })) { } serviceFiles;
in
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/vda";
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
        rootFsOptions = {
          compression = "lz4";
          acltype = "posixacl";
          xattr = "sa";
          relatime = "on";
          dnodesize = "auto";
          normalization = "formD";
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
            options = {
              mountpoint = "legacy";
              quota = "100G";
              "com.sun:auto-snapshot" = "false";
            };
          };
          "var/log" = {
            type = "zfs_fs";
            mountpoint = "/var/log";
            options = {
              mountpoint = "legacy";
              quota = "50G";
              recordsize = "128k";
              "com.sun:auto-snapshot" = "false";
            };
          };
          "var/lib" = {
            type = "zfs_fs";
            mountpoint = "/var/lib";
            options = {
              mountpoint = "legacy";
              reservation = "1G";
            };
          };
          "media" = {
            type = "zfs_fs";
            mountpoint = "/media";
            options = {
              mountpoint = "legacy";
              quota = "400G";
              recordsize = "1M";
              compression = "off";
              "com.sun:auto-snapshot" = "false";
            };
          };
        }
        // customDatasets;
      };
    };
  };
}
