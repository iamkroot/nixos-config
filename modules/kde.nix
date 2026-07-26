{
  config,
  pkgs,
  pii,
  ...
}:

{
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "${pii.primaryUser}";
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.defaultSession = "plasma";

  programs.xwayland.enable = true;

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
  ];

  environment.systemPackages = with pkgs; [
    kdePackages.krdp
  ];
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
  # for RDP
  networking.firewall.allowedTCPPorts = [ 3389 ];

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    elisa
    kate
    gwenview
  ];

  # KDE bug - getting recursive stack traces
  systemd.user.services."drkonqi-coredump-launcher@" = {
    enable = false;
  };
  systemd.user.services."drkonqi-coredump-processor@" = {
    enable = false;
  };
}
