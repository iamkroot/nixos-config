{ config, pii, ... }:
{
  services.nfs.server.enable = true;

  services.nfs.server.exports = ''
    ${pii.storage.media_main.mountpoint}  ${pii.hosts.homelab1.localIp}/24(rw,sync,no_subtree_check,no_root_squash)
    ${pii.storage.data_main.mountpoint}  ${pii.hosts.homelab1.localIp}/24(rw,sync,no_subtree_check,no_root_squash)
  '';

  networking.firewall.allowedTCPPorts = [ 2049 ];
}
