{
  config,
  osConfig,
  pkgs,
  pii,
  services,
  ...
}:

{
  imports = [
    ./tmux.nix
  ];
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    # atuin handles ctrl+r
    historyWidget.command = "";
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
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
      sync_address = "https://${osConfig.infra.services.hostnames.atuin}";

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
