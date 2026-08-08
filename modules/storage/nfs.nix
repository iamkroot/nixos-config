{
  pii,
  hostKey,
  ...
}:
let
  ip = pii.hosts.${hostKey}.localIp;
in
{
  services.nfs.server.enable = true;

  fileSystems."/export/media" = {
    device = pii.storage.media_main.mountpoint;
    fsType = "none";
    options = [
      "bind"
      "nofail"
    ];
    depends = [ pii.storage.media_main.mountpoint ];
  };

  fileSystems."/export/data" = {
    device = pii.storage.data_main.mountpoint;
    fsType = "none";
    options = [
      "bind"
      "nofail"
    ];
    depends = [ pii.storage.data_main.mountpoint ];
  };

  services.nfs.server.exports = ''
    /export        ${ip}/24(rw,fsid=0,no_subtree_check,crossmnt)
    /export/media  ${ip}/24(rw,sync,no_subtree_check,no_root_squash,nohide,fsid=1)
    /export/data   ${ip}/24(rw,sync,no_subtree_check,no_root_squash,nohide,fsid=2)
  '';

  networking.firewall.allowedTCPPorts = [ 2049 ];
}
