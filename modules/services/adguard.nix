{ config, pii, ... }:
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
  services.caddy.virtualHosts."${config.infra.services.hostnames.adguard}" = {
    extraConfig = ''
      import authelia
      reverse_proxy 127.0.0.1:${toString config.infra.services.ports.adguard}
    '';
    logFormat = ''
      output file /var/log/caddy/access-${config.infra.services.hostnames.adguard}.log {
        roll_size 50mb
        roll_keep 5
      }
    '';
  };
}
