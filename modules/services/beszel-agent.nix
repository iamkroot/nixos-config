{
  config,
  lib,
  ...
}:
let
  agentPort = config.infra.services.ports."beszel-${config.infra.hostKey}";
  isCloud = config.infra.hostKey == "cloud1";
in
{
  vaultix.secrets."beszel/agent_key" = { };

  vaultix.templates."beszel-agent.env" = {
    content = ''
      KEY=${config.vaultix.placeholder."beszel/agent_key"}
    '';
  };

  services.beszel.agent = {
    enable = true;
    openFirewall = false;
    environment = {
      PORT = toString agentPort;
    };
    environmentFile = config.vaultix.templates."beszel-agent.env".path;
  };

  # On cloud1, restrict agent port to Tailscale interface only
  networking.firewall.extraCommands = lib.mkIf isCloud ''
    iptables -A INPUT -i tailscale0 -p tcp --dport ${toString agentPort} -j ACCEPT
    iptables -A INPUT -p tcp --dport ${toString agentPort} -j DROP
  '';
}
