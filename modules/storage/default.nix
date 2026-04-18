{ config, ... }:
{
  imports = [
    ./luks-disks.nix
    ./media-pool.nix
    ./zfs-backup.nix
  ];

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
}
