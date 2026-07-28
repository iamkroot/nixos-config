{
  config,
  pkgs,
  lib,
  pii,
  myUtils,
  hostKey,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "jellyfin" { authelia = false; })
  ];

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    hardwareAcceleration = {
      enable = true;
      type = "vaapi";
      device = "/dev/dri/renderD128";
    };
    transcoding.enableHardwareEncoding = true;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Highly recommended for some decoding pipelines
    extraPackages = with pkgs; [
      libva
      libvdpau-va-gl
      vulkan-loader
      vulkan-validation-layers
      vulkan-extension-layer
    ];
  };

  # Create a dedicated group for media access
  users.groups.media = {
    gid = 993;
  };

  users.users."${pii.primaryUser}".extraGroups = [ "media" ];
  users.users.jellyfin.extraGroups = [
    "video"
    "render"
    "media"
  ];

  networking.firewall.extraCommands =
    let
      localIp = pii.hosts.${hostKey}.localIp;
    in
    ''
      # Allow TCP ${toString config.infra.services.ports.jellyfin} (HTTP) only from the ${localIp}/24 subnet
      iptables -A nixos-fw -s ${localIp}/24 -p tcp --dport ${toString config.infra.services.ports.jellyfin} -j nixos-fw-accept

      # Optional: Allow UDP 1900 and 7359 for Jellyfin auto-discovery (DLNA/Clients) on the local subnet
      iptables -A nixos-fw -s ${localIp}/24 -p udp --dport 1900 -j nixos-fw-accept
      iptables -A nixos-fw -s ${localIp}/24 -p udp --dport 7359 -j nixos-fw-accept
    '';

  # set data dir perms
  systemd.tmpfiles.rules = [
    # Type | Path | Mode | User | Group | Age | Argument
    "d /var/lib/jellyfin 0750 jellyfin media - -"
    "d /var/lib/jellyfin/data 0750 jellyfin media - -"
    "d /var/lib/jellyfin/data/trickplay 0770 jellyfin media - -"
    "d /var/lib/jellyfin/data/subtitles 0770 jellyfin media - -"
    "d /var/lib/jellyfin/transcodes 0770 jellyfin media - -"
  ];
}
