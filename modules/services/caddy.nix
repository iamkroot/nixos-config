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

      # ----------------------------------------------------
      # Anubis PoW Proxy with Local/Mesh IP Bypass
      # Usage: import anubis_proxy <target_backend> <anubis_backend>
      # ----------------------------------------------------
      (anubis_proxy) {
        @local remote_ip 127.0.0.1 ::1 private_ranges ${pii.networks.mesh.subnet} ${pii.networks.mesh.subnetV6}
        reverse_proxy @local {args[0]}
        reverse_proxy {args[1]} {
          header_up X-Real-IP {client_ip}
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
