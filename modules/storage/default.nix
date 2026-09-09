{
  pii,
  ...
}:
{
  imports = [
    ./luks-disks.nix
    ./media-pool.nix
    ./zfs-backup.nix
  ];

  # something for local media
  systemd.tmpfiles.rules = [
    # 1. Create the directory if it doesn't exist
    "d /media 0775 ${pii.primaryUser} media - -"
    "d /media/photos 0775 ${pii.primaryUser} media - -"

    # 2. Apply ACLs to the directory itself (Access ACL)
    "a /media - - - - group:media:rwx"
    "a /media/photos - - - - group:media:rwx"

    # 3. Ensure all NEW files/folders inherit these (Default ACL)
    "a /media - - - - default:group:media:rwx"
    "a /media/photos - - - - default:group:media:rwx"
  ];
}
