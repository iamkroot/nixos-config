{ config, pkgs, ... }:
{
  home.shellAliases = {
    "cat" = "bat";
    "fdi" = "fd -H -I";
    "rgi" = "rg --no-ignore --hidden";
    "ll" = "ls -laaB";
  };
}
