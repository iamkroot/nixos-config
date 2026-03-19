{
  config,
  pkgs,
  lib,
  pii,
  osConfig,
  ...
}:
{
  imports = [
    ../modules/zsh.nix
    ../modules/cli-tools.nix
    ../modules/aliases.nix
  ];
  programs.home-manager.enable = true;
  home.stateVersion = "26.05";
}
