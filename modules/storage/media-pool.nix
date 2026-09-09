{
  config,
  pkgs,
  lib,
  pii,
  ...
}:

let
  loadZfsScript = pkgs.writeShellScript "load-zfs-pool" (builtins.readFile ./load-zfs-pool.sh);
  ssd2 = pii.storage.ssd2;
  media_main = pii.storage.media_main;
  data_main = pii.storage.data_main;

  pools = [
    {
      name = ssd2.name;
      keys = {
        "${ssd2.name}-zfs-key" = ssd2.key;
      };
      autoBoot = true;
      hotplug = false;
    }
    {
      name = media_main.name;
      keys = {
        "${media_main.name}-zfs-key" = media_main.key;
        "${data_main.name}-data-zfs-key" = data_main.key;
      };
      autoBoot = false;
      hotplug = true;
      wantsTargets = [ "media-apps.target" ];
    }
  ];

  mediaServiceAttrs = {
    # Bind to the target so the app dies if the drive is exported
    bindsTo = [ "media-apps.target" ];
    after = [ "media-apps.target" ];
    wantedBy = [ "media-apps.target" ];
  };
in
{
  vaultix.secrets = lib.mkMerge (
    map (
      p:
      lib.mapAttrs (_: keyFile: {
        file = keyFile;
        owner = "root";
        group = "root";
      }) p.keys
    ) pools
  );

  boot.zfs.extraPools = map (p: p.name) pools;

  # This listens for any block device being added that is formatted
  # as a ZFS member and belongs to the pool.
  services.udev.extraRules = lib.concatMapStrings (
    p:
    lib.optionalString (p.hotplug or false) ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="zfs_member", ENV{ID_FS_LABEL}=="${p.name}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="load-${p.name}-keys.service"
    ''
  ) pools;

  systemd.services = lib.mkMerge (
    (map (p: {
      "zfs-import-${p.name}" = {
        serviceConfig = {
          ExecStop = "-${pkgs.zfs}/bin/zpool export ${p.name}";
        };
      };

      "load-${p.name}-keys" = {
        description = "Load encryption keys and mount datasets for ${p.name}";
        unitConfig.DefaultDependencies = false;

        requires = [
          "zfs-import-${p.name}.service"
          "vaultix-activate.service"
        ];
        after = [
          "zfs-import-${p.name}.service"
          "vaultix-activate.service"
        ];

        bindsTo = [ "zfs-import-${p.name}.service" ];
        before = [ "local-fs.target" ];
        wantedBy = lib.optional (p.autoBoot or false) "local-fs.target";
        wants = p.wantsTargets or [ ];

        path = [
          pkgs.zfs
          pkgs.coreutils
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${loadZfsScript} ${p.name}";
        };
      };
    }) pools)
    ++ [
      {
        jellyfin = lib.mkIf config.services.jellyfin.enable mediaServiceAttrs;
        podman-shoko-server = lib.mkIf (builtins.hasAttr "shoko-server" config.virtualisation.oci-containers.containers) mediaServiceAttrs;
      }
    ]
  );

  systemd.targets.media-apps = {
    description = "Target for all media-related services tied to media storage";
    bindsTo = [
      "load-${media_main.name}-keys.service"
      "load-${ssd2.name}-keys.service"
    ];
    after = [
      "load-${media_main.name}-keys.service"
      "load-${ssd2.name}-keys.service"
    ];
  };
}
