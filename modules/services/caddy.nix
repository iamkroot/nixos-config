{ config, pii, ... }:
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  services.caddy = {
    enable = true;
    email = pii.primaryEmail;

    extraConfig = ''
      # ----------------------------------------------------
      # Authelia Forward Auth Snippet
      # ----------------------------------------------------
      (authelia) {
        forward_auth 127.0.0.1:${toString config.infra.services.ports.authelia} {
          uri /api/verify?rd=https://${config.infra.services.hostnames.auth}/
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
      }
    '';
  };
}
