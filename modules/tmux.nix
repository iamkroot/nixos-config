{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "tmux-256color";
    historyLimit = 100000;

    mouse = true;
    baseIndex = 1; # Start windows at 1, not 0
    escapeTime = 0;
    aggressiveResize = true;

    plugins = with pkgs.tmuxPlugins; [
      sensible # Basic settings everyone expects
      yank # Better system clipboard support
    ];

    extraConfig = ''
      set -s set-clipboard on
      # Split panes using | and -
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Custom status bar info (Useful for Homelabs)
      set -g status-right '#[fg=green,bg=default,bright] ⚡ %H:%M #[default]'
    '';
  };
}
