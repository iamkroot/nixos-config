{ config, pkgs, ... }:

{
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  services.desktopManager.plasma6.enable = true;

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
}
