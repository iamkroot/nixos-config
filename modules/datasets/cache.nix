{
  pii,
  ...
}:
let
  user = pii.primaryUser;
in
{
  "home/cache" = {
    type = "zfs_fs";
    mountpoint = "/home/${user}/.cache";
    options = {
      mountpoint = "legacy";
      sync = "disabled";
      "sanoid:autosnap" = "false";
      "syncoid:sync" = "no";
    };
  };
}
