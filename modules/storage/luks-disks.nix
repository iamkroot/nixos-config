{ config, pii, ... }:
let
  disk1 = pii.storage.disk1;
in
{
  vaultix.secrets."${disk1.name}-luks-key" = {
    file = disk1.luks-key;
    owner = "root";
    group = "root";
  };

  environment.etc.crypttab.text =
    let
      disk1-key = config.vaultix.secrets."${disk1.name}-luks-key".path;
    in
    ''
      # <target name>  <source device>       <key file>    <options>
      ${disk1.name}     UUID=${disk1.uuid}   ${disk1-key}  nofail,noauto,x-systemd.device-timeout=5s
    '';

  fileSystems."/mnt/${disk1.name}" = {
    device = "/dev/mapper/${disk1.name}";
    fsType = "ext4";
    options = [
      "nofail"
      "noauto"
      # makes it easy to just "systemctl start mnt-disk.mount"
      "x-systemd.requires=systemd-cryptsetup@${disk1.name}.service"
    ];
  };

  # Automatically unlock when the physical drive is plugged in, and mount when the mapper block device appears.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${disk1.uuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="systemd-cryptsetup@${disk1.name}.service"
    ACTION=="add", SUBSYSTEM=="block", ENV{DM_NAME}=="${disk1.name}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-${disk1.name}.mount"
  '';

  # Propagate stop from the mount unit to cryptsetup so "systemctl stop mnt-${disk1.name}.mount" also closes LUKS.
  systemd.services."systemd-cryptsetup@${disk1.name}" = {
    overrideStrategy = "asDropin";
    partOf = [ "mnt-${disk1.name}.mount" ];
  };
}
