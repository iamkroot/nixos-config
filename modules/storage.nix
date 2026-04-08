{ config, pii, ... }:
let
  disk1 = pii.storage.disk1;
  disk2 = pii.storage.disk2;
  disk3 = pii.storage.disk3;
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
      "x-systemd.automount"
    ];
  };

  # something for local media
  systemd.tmpfiles.rules = [
    # 1. Create the directory if it doesn't exist
    "d /media 0775 root media - -"

    # 2. Apply ACLs to the directory itself (Access ACL)
    "A /media - - - - group:media:rwx"

    # 3. Ensure all NEW files/folders inherit these (Default ACL)
    "A /media - - - - default:group:media:rwx"

    # 4. (Optional) Fix existing files if you just migrated
    "Z /media 0775 root media - -"
  ];
  vaultix.secrets."${disk2.name}-zfs-key" = {
    file = disk2.key;
    owner = "root";
    group = "root";
  };
  vaultix.secrets."${disk3.name}-zfs-key" = {
    file = disk3.key;
    owner = "root";
    group = "root";
  };
}
