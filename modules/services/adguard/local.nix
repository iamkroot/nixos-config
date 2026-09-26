{
  config,
  pkgs,
  pii,
  myUtils,
  hostKey,
  lib,
  ...
}:
let
  cfg = config.infra.dns.adguard;
  isLocal = cfg.location == "local" || cfg.location == "homelab1" || cfg.location == hostKey;
  hostname = config.infra.services.hostnames.adguard;

  caddyConfig =
    (myUtils.mkCaddyModule "adguard" {
      authelia = true;
      targetHost = "127.0.0.1";
      bypassAuthPaths = [ "/dns-query*" ];
      extraHostConfig = {
        useACMEHost = hostname;
      };
    })
      { inherit config pii; };
in
{
  config = lib.mkIf (cfg.enable && isLocal) (
    lib.mkMerge [
      caddyConfig
      {
        networking.firewall.allowedTCPPorts = [ 53 ];
        networking.firewall.allowedUDPPorts = [ 53 ];

        services.adguardhome = {
          enable = true;

          settings = {
            port = config.infra.services.ports.adguard;
            dns = {
              bind_hosts = [ "0.0.0.0" ];
              port = 53;
              upstream_dns = [
                "https://dns.cloudflare.com/dns-query"
                "8.8.8.8"
              ];
            };
            tls = {
              enabled = true;
              server_name = hostname;
              port_dns_over_tls = 853; # TCP
              port_dns_over_quic = 853; # UDP

              # WARNING: AdGuard runs as the 'adguardhome' user.
              # It MUST have read permissions to wherever these files live.
              certificate_path = "/var/lib/acme/${hostname}/cert.pem";
              private_key_path = "/var/lib/acme/${hostname}/key.pem";
            };

            # Bypass Hairpin NAT
            filtering = {
              enabled = true;
              rewrites = [
                {
                  # Wildcard rewrite: sends all subdomains to Caddy server's LAN IP
                  domain = "*.${config.infra.domain}";
                  answer = "${pii.hosts.${hostKey}.localIp}";
                  enabled = true;
                }
                {
                  # Base domain rewrite
                  domain = "${config.infra.domain}";
                  answer = "${pii.hosts.${hostKey}.localIp}";
                  enabled = true;
                }
              ];
            };
          };
        };

        systemd.services.adguardhome = {
          # 1. Don't start AdGuard until the certificate is successfully generated
          wants = [ "acme-${hostname}.cert.service" ];
          after = [
            "acme-${hostname}.cert.service"
            "systemd-tmpfiles-setup.service"
          ];

          serviceConfig = {
            # 2. Grant the dynamic user read access to the ACME group
            SupplementaryGroups = [ "adguard-cert" ];
          };
        };

        vaultix.secrets."duckdns-token".file = "${pii.duckdnsToken}";

        security.acme.certs.${hostname} = {
          dnsProvider = "duckdns";
          credentialFiles = {
            "DUCKDNS_TOKEN_FILE" = config.vaultix.secrets.duckdns-token.path;
          };
          group = "adguard-cert";
        };

        users.groups.adguard-cert = { };
        systemd.tmpfiles.rules = [
          "d /var/lib/acme/${hostname} 0750 acme adguard-cert - -"
          "z /var/lib/acme/${hostname}/* 0640 acme adguard-cert - -"
        ];
        users.users.caddy.extraGroups = [ "adguard-cert" ];
      }
    ]
  );
}
