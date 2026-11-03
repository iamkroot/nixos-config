{
  config,
  pkgs,
  pii,
  lib,
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
  networking.firewall.allowedTCPPorts = [ config.infra.services.ports.krdp ];

  systemd.user.services."app-org.kde.krdpserver" = {
    description = "KRDP Server";
    after = [
      "plasma-xdg-desktop-portal-kde.service"
      "plasma-core.target"
    ];
    partOf = [ "plasma-workspace.target" ];
    wantedBy = [ "plasma-workspace.target" ];
    aliases = [ "plasma-krdp_server.service" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.kdePackages.krdp}/bin/krdpserver --port ${toString config.infra.services.ports.krdp}";
      Restart = "on-abnormal";
      RestartSec = "3s";
    };
  };

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    elisa
    kate
    gwenview
  ];

  # KDE bug - getting recursive stack traces
  systemd.services."drkonqi-coredump-launcher@" = {
    enable = false;
    wantedBy = lib.mkForce [ ];
  };
  systemd.services."drkonqi-coredump-processor@" = {
    enable = false;
    wantedBy = lib.mkForce [ ];
  };
  systemd.user.services."drkonqi-coredump-launcher@" = {
    enable = false;
  };
  systemd.user.services."drkonqi-coredump-processor@" = {
    enable = false;
  };
}
