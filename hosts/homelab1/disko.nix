{
  inputs,
  lib,
  pii,
  ...
}:
let
  serviceFiles = [
    (inputs.self + /modules/datasets/jellyfin.nix)
    (inputs.self + /modules/datasets/shoko.nix)
    (inputs.self + /modules/datasets/authelia.nix)
  ];

  customDatasets = lib.foldl' (acc: path: acc // (import path { })) { } serviceFiles;

  externalDisks = lib.remove null (
    lib.unique (lib.mapAttrsToList (name: value: lib.attrByPath [ "name" ] null value) pii.storage)
  );
in
{
  disko.zfs = {
    enable = true;
    settings = {
      ignoredDatasets = [
        "zroot/root"
      ]
      ++ lib.concatMap (d: [
        d
        "${d}/*"
      ]) externalDisks;
      ignoredProperties = [
        "keylocation"
        "nixos:shutdown-time"
      ];
    };
  };
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
            swap = {
              size = "8G";
              content = {
                type = "swap";
                # no hibernation
                resumeDevice = false;
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
          # relatime = "on";
          atime = "off";
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
            options = {
              mountpoint = "legacy";
              quota = "100G";
              # Guarantee that 20GB is always available for /nix
              reservation = "20G";
              "sanoid:autosnap" = "false";
            };
          };
          "var/log" = {
            type = "zfs_fs";
            mountpoint = "/var/log";
            options = {
              mountpoint = "legacy";
              quota = "50G";
              recordsize = "128k";
              "sanoid:autosnap" = "false";
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
              "sanoid:autosnap" = "false";
            };
          };
        }
        // customDatasets;
      };
    };
  };
}
