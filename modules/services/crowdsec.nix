{
  inputs,
  pii,
  config,
  ...
}:
{
  disabledModules = [
    "services/security/crowdsec.nix"
    "services/security/crowdsec-firewall-bouncer.nix"
  ];

  imports = [
    "${inputs.crowdsec}/nixos/modules/services/security/crowdsec.nix"
    "${inputs.crowdsec}/nixos/modules/services/security/crowdsec-firewall-bouncer.nix"
  ];

  services.crowdsec = {
    enable = true;
    settings.config.api.server.listen_uri = "0.0.0.0:${toString config.infra.services.ports.crowdsec}";

    extraGroups = [ "caddy" ];

    hub.collections = [
      "crowdsecurity/caddy"
      "crowdsecurity/linux"
      "crowdsecurity/base-http-scenarios"
      "Dominic-Wagner/vaultwarden"
      "LePresidente/gitea"
    ];

    settings.acquisitions = [
      {
        filenames = [ "/var/log/caddy/*.log" ];
        labels.type = "caddy";
      }
      {
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=vaultwarden.service" ];
        labels.type = "vaultwarden";
      }
      {
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=forgejo.service" ];
        labels.type = "gitea";
      }
    ];
  };

  # Whitelist local network addresses
  environment.etc."crowdsec/parsers/s02-enrich/private-whitelist.yaml".text = ''
    name: custom/private-whitelist
    description: "Whitelist internal private network"
    whitelist:
      reason: "Private network ${pii.hosts.homelab1.localIp}/24"
      cidr:
        - "${pii.hosts.homelab1.localIp}/24"
  '';

  # Drops the connections at the kernel/firewall level
  services.crowdsec-firewall-bouncer = {
    enable = true;
  };

  # Ensure Caddy creates new log files with group-read permissions (0640)
  # rather than default strict permissions (0600)
  systemd.services.caddy.serviceConfig.UMask = "0027";

  # Ensure log and data directories are assigned correct group-readable permissions
  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
    "z /var/log/caddy/*.log 0640 caddy caddy -"
    "d /var/lib/crowdsec 0750 crowdsec crowdsec -"
    "Z /var/lib/crowdsec 0750 crowdsec crowdsec -"
  ];
}
