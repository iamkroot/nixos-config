{
  config,
  pii,
  lib,
  ...
}:
{
  # Dynamically register all secrets used by VPN servers (root-owned)
  vaultix.secrets = lib.genAttrs (map (s: s.secret) pii.vpn.servers) (_: { });

  # Allows binding to tailscaleIp immediately at boot even before tailscaled is up
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  services.sing-box = {
    enable = true;
    settings = {
      dns.servers = [
        {
          tag = "vpn-dns";
          type = "udp";
          server = pii.vpn.dns;
          detour = "vpn-out";
        }
      ];

      inbounds = [
        {
          tag = "mixed-tailscale";
          type = "mixed";
          listen = pii.hosts.homelab1.tailscaleIp;
          listen_port = config.infra.services.ports.vpn-proxy;
        }
        {
          tag = "mixed-loopback";
          type = "mixed";
          listen = "127.0.0.1";
          listen_port = config.infra.services.ports.vpn-proxy;
        }
      ];

      endpoints = map (s: {
        type = "wireguard";
        tag = s.tag;
        address = [ pii.vpn.assignedIp ];
        private_key._secret = config.vaultix.secrets.${s.secret}.path;
        peers = [
          {
            address = s.address;
            port = s.port;
            public_key = s.publicKey;
            allowed_ips = [ "0.0.0.0/0" ];
          }
        ];
      }) pii.vpn.servers;

      outbounds = [
        {
          type = "urltest";
          tag = "vpn-out";
          outbounds = map (s: s.tag) pii.vpn.servers;
          # Uses built-in defaults: https://www.gstatic.com/generate_204, 3m interval, 50ms tolerance
        }
      ];

      route = {
        final = "vpn-out";
        default_domain_resolver = "vpn-dns";
      };
    };
  };
}
