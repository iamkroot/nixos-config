{
  config,
  lib,
  pii,
  ...
}:
let
  myServices = config.myServices;

  datasetsDir = ../../modules/datasets;
  dirContents = builtins.readDir datasetsDir;

  isDatasetEnabled =
    fileName:
    let
      stem = lib.removeSuffix ".nix" fileName;
      directService = myServices.${stem} or null;
      moduleServices = lib.filterAttrs (_: s: s.module == stem) myServices;
    in
    if directService != null then
      directService.enable && directService.host == "homelab1"
    else if moduleServices != { } then
      lib.any (s: s.enable && s.host == "homelab1") (builtins.attrValues moduleServices)
    else
      true;

  enabledDatasetFiles = lib.filterAttrs (
    file: type:
    (type == "regular" || type == "symlink")
    && lib.hasSuffix ".nix" file
    && !lib.hasPrefix "." file
    && file != "default.nix"
    && isDatasetEnabled file
  ) dirContents;

  serviceFiles = map (file: datasetsDir + "/${file}") (builtins.attrNames enabledDatasetFiles);

  customDatasetsRaw = lib.foldl' (
    acc: path: acc // (import path { inherit pii lib; })
  ) { } serviceFiles;
  customDatasets = lib.mapAttrs (
    name: value:
    value
    // {
      mountOptions = (value.mountOptions or [ ]) ++ [
        "nofail"
        "x-systemd.after=disko-zfs.service"
      ];
    }
  ) customDatasetsRaw;

  externalDisks = lib.subtractLists [ null "zroot" ] (
    lib.unique (lib.mapAttrsToList (name: value: lib.attrByPath [ "name" ] null value) pii.storage)
  );
in
{
  imports = [
    ../../modules/services-schema.nix
  ];

  disko.zfs = {
    enable = true;
    settings = {
      # logLevel = "trace";
      ignoredDatasets = [
        "zroot/root"
      ]
      ++ lib.concatMap (d: [
        d
        "${d}/*"
      ]) externalDisks;
      ignoredProperties = [
        "keylocation"
        "keyformat"
        "encryption"
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
              "syncoid:sync" = "no";
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
              "syncoid:sync" = "no";
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
          "var/lib/containers" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/containers";
            options = {
              mountpoint = "legacy";
              "sanoid:autosnap" = "false";
              "syncoid:sync" = "no";
              relatime = "on";
            };
          };
        }
        // customDatasets;
      };
    };
  };
}
