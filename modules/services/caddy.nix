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
      # for caddy
      PORKBUN_API_SECRET=${config.vaultix.placeholder."porkbun-secret-key"}
      # for lego
      PORKBUN_SECRET_API_KEY=${config.vaultix.placeholder."porkbun-secret-key"}
    '';
  };

  services.caddy = {
    enable = true;
    email = pii.primaryEmail;

    # Custom Caddy build with Porkbun DNS plugin for DNS-01 ACME
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/porkbun@v0.3.1" ];
      hash = "sha256-CjL8dMdnsiawaPiQGRvL3he4Ydd3nIbQs6tBWMwUbaw=";
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
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = pii.primaryEmail;
      dnsProvider = "porkbun";
      environmentFile = config.vaultix.templates."caddy-porkbun.env".path;
    };
    certs."${config.infra.domain}" = {
      domain = "*.${config.infra.domain}";
      group = config.services.caddy.group;
    };
  };

  # Load Porkbun env vars into the Caddy service
  systemd.services.caddy.serviceConfig.EnvironmentFile = [
    config.vaultix.templates."caddy-porkbun.env".path
  ];
}
