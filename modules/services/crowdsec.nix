{ ... }:
{
  services.crowdsec = {
    enable = true;

    hub.collections = [
      "crowdsecurity/caddy"
      "crowdsecurity/linux"
      "crowdsecurity/base-http-scenarios"
    ];

    # Tell CrowdSec where to find the logs we generated with `mkSecureHost`
    localConfig.acquisitions = [
      {
        filenames = [ "/var/log/caddy/*.log" ];
        labels.type = "caddy";
      }
    ];
  };

  # 2. The Muscle: Drops the connections at the kernel/firewall level
  services.crowdsec-firewall-bouncer = {
    enable = true;
  };

  # 3. The Permissions Fix: Let CrowdSec read Caddy's logs
  # Add the crowdsec user to the caddy group
  users.users.crowdsec.extraGroups = [ "caddy" ];

  # Ensure Caddy creates new log files with group-read permissions (0640)
  # rather than default strict permissions (0600)
  systemd.services.caddy.serviceConfig.UMask = "0027";
}
