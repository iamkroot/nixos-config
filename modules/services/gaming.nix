{
  config,
  pkgs,
  lib,
  pii,
  ...
}:
let
  user = pii.primaryUser;
  gamingDatasets = import ../datasets/gaming.nix { inherit pii; };
  datasetMountpoints = lib.filter (m: m != "none") (
    lib.mapAttrsToList (name: ds: ds.mountpoint or "none") gamingDatasets
  );
in
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

  users.users."${user}".extraGroups = [
    "input"
    "video"
    "render"
    "gamemode"
  ];

  systemd.tmpfiles.rules = map (dir: "d ${dir} 0755 ${user} users - -") datasetMountpoints;
}
