{
  config,
  pkgs,
  lib,
  pii,
  ...
}:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  programs.gamemode.enable = true;

  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true; # Automatically opens TCP 47984-47990 & UDP 47998-48010
    capSysAdmin = true; # Grants Wayland KMS framebuffer capture permissions
  };

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        MulticastDNS = "yes";
      };
    };
  };
  networking.firewall.allowedUDPPorts = [ 5353 ]; # Open mDNS UDP port for local discovery

  environment.systemPackages = with pkgs; [
    libva-utils
    vulkan-tools
    mangohud
  ];

  users.users."${pii.primaryUser}".extraGroups = [
    "input"
    "video"
    "render"
    "gamemode"
  ];
}
