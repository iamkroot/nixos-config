{
  config,
  osConfig,
  pkgs,
  pii,
  ...
}:

{
  imports = [
    ./tmux.nix
  ];
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
  };

  programs.fd = {
    enable = true;
  };

  programs.ripgrep = {
    enable = true;
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      style = "numbers,changes,header";
    };
  };

  programs.jq = {
    enable = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      sync_address = "http://${pii.hosts.homelab1.localIp}:${toString osConfig.infra.services.ports.atuin}";

      search_mode = "fuzzy";
      style = "compact";
      auto_sync = true;
    };
    flags = [
      "--disable-up-arrow"
    ];
  };

  programs.aria2 = {
    enable = true;
    settings = {
      max-connection-per-server = 4;
      split = 4;
      continue = "true";
    };
  };
}
