{
  config,
  pkgs,
  pii,
  ...
}:
{
  vaultix.secrets."duckdns-token".file = "${pii.duckdnsToken}";
  systemd.services.duckdns-update = {
    description = "Update DuckDNS IP";
    requires = [ "vaultix-activate.service" ];
    after = [
      "network-online.target"
      "vaultix-activate.service"
    ];
    wants = [ "network-online.target" ];

    # Loads the token into an environment variable so it stays out of the Nix store
    serviceConfig = {
      Type = "oneshot";
    };

    script = ''
      # Read the token from the securely loaded credential
      TOKEN=$(cat "${config.vaultix.secrets.duckdns-token.path}")
      DOMAIN="${pii.nick}"

      # Ping DuckDNS. Leaving the 'ip=' parameter blank tells DuckDNS to auto-detect your IP
      ${pkgs.curl}/bin/curl -s -K- <<< "url = \"https://www.duckdns.org/update?domains=$DOMAIN&token=$TOKEN&ip=\""
    '';
  };

  systemd.timers.duckdns-update = {
    description = "Timer to update DuckDNS IP";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m"; # Runs every 5 minutes
      Unit = "duckdns-update.service";
    };
  };
}
