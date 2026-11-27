{
  config,
  pii,
  ...
}:
let
  turnPort = config.infra.services.ports.coturn;
  hostname = config.infra.services.hostnames.coturn;
  relayMinPort = config.infra.services.ports.coturn_relay_min;
  relayMaxPort = config.infra.services.ports.coturn_relay_max;
in
{
  vaultix.secrets."coturn/auth_secret" = {
    owner = "turnserver";
  };

  services.coturn = {
    enable = true;
    use-auth-secret = true;
    static-auth-secret-file = config.vaultix.secrets."coturn/auth_secret".path;
    listening-port = turnPort;
    realm = hostname;
    no-tls = true;
    no-dtls = true;
    no-cli = true;
    min-port = relayMinPort;
    max-port = relayMaxPort;
    extraConfig = ''
      external-ip=${pii.hosts.cloud1.publicIp}
      no-loopback-peers
      no-multicast-peers
    '';
  };

  networking.firewall.allowedTCPPorts = [ turnPort ];
  networking.firewall.allowedUDPPorts = [ turnPort ];
  networking.firewall.allowedUDPPortRanges = [
    {
      from = relayMinPort;
      to = relayMaxPort;
    }
  ];
}
