{
  config,
  pii,
  hostKey,
  ...
}:
let
  ip = pii.hosts.${hostKey}.localIp;
  meshNet = pii.networks.mesh.subnet;
in
{
  services.nfs.server.enable = true;

  fileSystems."/export/media" = {
    device = pii.storage.media_main.mountpoint;
    fsType = "none";
    options = [
      "rbind"
      "nofail"
      "noauto"
      "x-systemd.requires=media-apps.target"
      "x-systemd.after=media-apps.target"
      "x-systemd.wanted-by=media-apps.target"
      "x-systemd.binds-to=media-apps.target"
    ];
  };

  fileSystems."/export/data" = {
    device = pii.storage.data_main.mountpoint;
    fsType = "none";
    options = [
      "rbind"
      "nofail"
      "noauto"
      "x-systemd.requires=media-apps.target"
      "x-systemd.after=media-apps.target"
      "x-systemd.wanted-by=media-apps.target"
      "x-systemd.binds-to=media-apps.target"
    ];
  };

  systemd.targets.media-apps.wants = [
    "export-media.mount"
    "export-data.mount"
  ];

  systemd.services.nfs-server = {
    after = [ "media-apps.target" ];
  };

  services.nfs.server.exports = ''
    /export        ${ip}/24(rw,fsid=0,no_subtree_check,crossmnt) ${meshNet}(rw,fsid=0,no_subtree_check,crossmnt)
    /export/media  ${ip}/24(rw,async,no_subtree_check,no_root_squash,nohide,crossmnt,fsid=1) ${meshNet}(rw,async,no_subtree_check,no_root_squash,nohide,crossmnt,fsid=1)
    /export/data   ${ip}/24(rw,async,no_subtree_check,no_root_squash,nohide,crossmnt,fsid=2) ${meshNet}(rw,async,no_subtree_check,no_root_squash,nohide,crossmnt,fsid=2)
  '';

  networking.firewall.allowedTCPPorts = [ config.infra.services.ports.nfs ];
}
