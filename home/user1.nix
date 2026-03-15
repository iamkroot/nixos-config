{ config, pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
  programs.home-manager.enable = true;
  home.stateVersion = "26.05";
}
