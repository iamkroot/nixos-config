{
  host,
  config,
  pkgs,
  lib,
  pii,
  inputs,
  ...
}:

{
  home.packages = [
    inputs.zsh-patina.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
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

    autosuggestion.enable = true;
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
      # {
      #   name = "fast-syntax-highlighting";
      #   src = pkgs.zsh-fast-syntax-highlighting;
      #   file = "share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh";
      # }
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
        # Hide "." and ".." in completion menus
        zstyle ':completion:*' special-dirs false
        # Sort by last accessed time
        zstyle ':completion:*' file-sort modification
        # don't sort checkout results
        zstyle ':completion:*:git-checkout:*' sort false
        zstyle ':completion:*:usage:*' sort false
        zstyle ':completion:*:mise:*' sort false
        zstyle ':completion:*:descriptions' format '[%d]'
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
        zstyle ':completion:*' menu no
        # Preview
        zstyle ':fzf-tab:complete:eza:*' fzf-preview '[ -d "$realpath" ] && eza -1 --color=always "$realpath" || bat -n --color=always "$realpath"'
        zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always "$realpath"'
        # zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
        zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind backward-eof:abort
        zstyle ':fzf-tab:*' switch-group '<' '>'

        # give a preview of commandline arguments when completing `kill`
        zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
        zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
          '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'
        zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags --preview-window=down:3:wrap


        autoload -Uz copy-earlier-word
        zle -N copy-earlier-word
        bindkey "^[m" copy-earlier-word

        # use alt+w to delete entire word till space
        autoload -Uz backward-kill-word-match
        zle -N backward-kill-shell-word backward-kill-word-match
        zstyle :zle:backward-kill-shell-word word-style shell
        bindkey "^[w" backward-kill-shell-word

        if [ -f "$HOME/.dotfiles/.zshrc-nix-extra" ]; then
          source "$HOME/.dotfiles/.zshrc-nix-extra"
        fi

        if [ -f "$HOME/.dotfiles/.p10k.zsh" ]; then
          source "$HOME/.dotfiles/.p10k.zsh"
        elif [ -f "$HOME/.p10k.zsh" ]; then
          source "$HOME/.p10k.zsh"
        fi
        eval "$(zsh-patina activate)"
      '')
    ];
  };
}
