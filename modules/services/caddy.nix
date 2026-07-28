{
  config,
  pkgs,
  pii,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Porkbun secrets for Caddy DNS-01 ACME
  vaultix.secrets."porkbun-api-key".file = "${pii.porkbun.apiKey}";
  vaultix.secrets."porkbun-secret-key".file = "${pii.porkbun.secretKey}";

  # Render Porkbun credentials as an EnvironmentFile for Caddy
  vaultix.templates."caddy-porkbun.env" = {
    content = ''
      PORKBUN_API_KEY=${config.vaultix.placeholder."porkbun-api-key"}
      PORKBUN_API_SECRET=${config.vaultix.placeholder."porkbun-secret-key"}
    '';
  };

  services.caddy = {
    enable = true;
    email = pii.primaryEmail;

    # Custom Caddy build with Porkbun DNS plugin for DNS-01 ACME
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/porkbun@v0.3.1" ];
      hash = "sha256-JtzeWz9GdW/+1Qft5nU9diPkFQvPGxQkgR8n8w+ryoI=";
    };

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

    # Use DNS-01 challenge globally via Porkbun — works for LAN-only services and wildcards
    globalConfig = ''
      acme_dns porkbun {
        api_key {env.PORKBUN_API_KEY}
        api_secret_key {env.PORKBUN_API_SECRET}
      }
    '';
  };

  # Load Porkbun env vars into the Caddy service
  systemd.services.caddy.serviceConfig.EnvironmentFile = [
    config.vaultix.templates."caddy-porkbun.env".path
  ];
}
