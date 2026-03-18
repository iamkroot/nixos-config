{
  config,
  pkgs,
  lib,
  pii,
  osConfig,
  ...
}:
let
  link = config.lib.file.mkOutOfStoreSymlink;
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  imports = [
    ../modules/zsh.nix
    ../modules/cli-tools.nix
  ];

  xdg.configFile."mise/config.toml".source = link "${dotfiles}/.config/mise/config.toml";
  home.activation.cloneDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # If the dotfiles repo doesn't exist on this machine, clone it
    if [ ! -d "${dotfiles}" ]; then
      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh"
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone "${pii.dotfilesRepo}" "${dotfiles}"
    fi
  '';

  programs.git = {
    enable = true;
    userName = "${pii.nick}";
    userEmail = "${pii.primaryEmail}";
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      gpg.format = "ssh";
      user.signingkey = osConfig.vaultix.secrets."ssh-key".path;
      commit.gpgsign = true;
    };
  };
  programs.ssh = {
    enable = true;
    matchBlocks."github.com" = {
      hostname = "github.com";
      user = "git";
      identityFile = osConfig.vaultix.secrets."github-ssh-key".path;
    };
  };
  programs.home-manager.enable = true;
  home.stateVersion = "26.05";
}
