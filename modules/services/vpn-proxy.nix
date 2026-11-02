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
      dns = {
        servers = [
          {
            tag = "vpn-dns";
            type = "udp";
            server = pii.vpn.dns;
            detour = "vpn-out";
          }
          {
            tag = "local-dns";
            type = "udp";
            server = pii.router2.localIp;
            detour = "direct";
          }
        ];
        rules = [
          {
            domain_suffix = [
              pii.primaryDomain
              "local"
              "lan"
              "ts.net"
              "arpa"
              "localhost"
            ];
            server = "local-dns";
            strategy = "prefer_ipv4";
          }
        ];
        final = "vpn-dns";
        strategy = "ipv4_only";
      };

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
          url = "http://1.1.1.1/generate_204";
          interval = "3m";
          tolerance = 50;
        }
        {
          type = "direct";
          tag = "direct";
          domain_resolver = "local-dns";
        }
      ];

      route = {
        rules = [
          {
            ip_is_private = true;
            outbound = "direct";
          }
          {
            ip_cidr = [
              pii.networks.mesh.subnet
              pii.networks.mesh.subnetV6
            ];
            outbound = "direct";
          }
          {
            domain_suffix = [
              pii.primaryDomain
              "local"
              "lan"
              "ts.net"
              "localhost"
            ];
            outbound = "direct";
          }
        ];
        final = "vpn-out";
        default_domain_resolver = "vpn-dns";
      };
    };
  };
}
