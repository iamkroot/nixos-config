{ config, pkgs, ... }:
{
  home.shellAliases = {
    "bat" = "cat";
    "fdi" = "fd -H -I";
    "rgi" = "rg --no-ignore --hidden";
    "ll" = "ls -laaB";
  };
}
