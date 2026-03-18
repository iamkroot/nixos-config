{
  config,
  pkgs,
  pii,
  ...
}:
{
  imports = [
    ../modules/zsh.nix
  ];
  programs.git = {
    enable = true;
    userName = "${pii.nick}";
    userEmail = "${pii.primaryEmail}";
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      gpg.format = "ssh";
      user.signingkey = "~/.ssh/id_ed25519";
      commit.gpgsign = true;
    };
  };
  programs.ssh = {
    enable = true;
    matchBlocks."github.com" = {
      hostname = "github.com";
      user = "git";
      identityFile = "~/.ssh/github_ed25519";
    };
  };
  programs.home-manager.enable = true;
  home.stateVersion = "26.05";
}
