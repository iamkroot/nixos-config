{
  host,
  config,
  pkgs,
  lib,
  pii,
  ...
}:

{
  programs.zsh = {
    enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "systemd"
        "z"
      ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    # Use mkMerge to combine your top and bottom scripts safely
    initContent = lib.mkMerge [

      # This replaces initExtraFirst (Forces it to the VERY TOP of .zshrc)
      (lib.mkBefore ''
        # Enable Powerlevel10k instant prompt.
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')

      # This replaces initExtra (Forces it to the VERY BOTTOM of .zshrc)
      (lib.mkAfter ''
        if [ -f "$HOME/.dotfiles/.zshrc-nix-extra" ]; then
          source "$HOME/.dotfiles/.zshrc-nix-extra"
        fi

        if [ -f "$HOME/.dotfiles/.p10k.zsh" ]; then
          source "$HOME/.dotfiles/.p10k.zsh"
        elif [ -f "$HOME/.p10k.zsh" ]; then
          source "$HOME/.p10k.zsh"
        fi
      '')
    ];
  };
}
