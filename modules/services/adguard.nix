{
  config,
  pii,
  myUtils,
  ...
}:
let
  hostname = config.infra.services.hostnames.adguard;
in
{
  imports = [
    (myUtils.mkCaddyModule "adguard" {
      authelia = true;
      extraHostConfig = {
        useACMEHost = hostname;
      };
    })
  ];
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
            answer = "${pii.hosts.homelab1.localIp}";
            enabled = true;
          }
          {
            # Base domain rewrite
            domain = "${config.infra.domain}";
            answer = "${pii.hosts.homelab1.localIp}";
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
