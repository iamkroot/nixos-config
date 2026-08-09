{
  pkgs,
  lib,
  config,
  ...
}:
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
    port = config.infra.services.ports.tailscale;
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
