{
  config,
  pkgs,
  lib,
  pii,
  ...
}:
{
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      libva
      libvdpau-va-gl
    ];
  };

  # Create a dedicated group for media access
  users.groups.media = { };

  users.users."${pii.primaryUser}".extraGroups = [ "media" ];
  users.users.jellyfin.extraGroups = [
    "video"
    "render"
    "media"
  ];

  services.caddy.virtualHosts."${config.infra.services.hostnames.jellyfin}" = {
    extraConfig = ''
      reverse_proxy 127.0.0.1:8096
    '';
  };

  networking.firewall.extraCommands =
    let
      localIp = pii.hosts.homelab1.localIp;
    in
    ''
      # Allow TCP 8096 (HTTP) only from the ${localIp}/24 subnet
      iptables -A nixos-fw -s ${localIp}/24 -p tcp --dport 8096 -j nixos-fw-accept

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
