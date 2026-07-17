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
      ${disk1.name}     UUID=${disk1.uuid}   ${disk1-key}  nofail,x-systemd.device-timeout=5s
    '';

  fileSystems."/mnt/${disk1.name}" = {
    device = "/dev/mapper/${disk1.name}";
    fsType = "ext4";
    options = [
      "nofail"
    ];
  };

  # When the LUKS volume is unlocked and the device mapper block device appears, trigger the systemd mount unit.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{DM_NAME}=="${disk1.name}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-${disk1.name}.mount"
  '';
}
