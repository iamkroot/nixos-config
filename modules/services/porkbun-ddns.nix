# Porkbun DDNS updater — replaces DuckDNS.
# Updates the A record for <domain> every 5 minutes via Porkbun API.
{
  config,
  pkgs,
  pii,
  hostKey,
  ...
}:
{
  vaultix.secrets."porkbun-api-key".file = "${pii.porkbun.apiKey}";
  vaultix.secrets."porkbun-secret-key".file = "${pii.porkbun.secretKey}";

  systemd.services.porkbun-ddns = {
    description = "Update Porkbun DDNS record for ${pii.hosts.${hostKey}.name}.${config.infra.domain}";
    requires = [ "vaultix-activate.service" ];
    after = [
      "network-online.target"
      "vaultix-activate.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    script =
      let
        curl = "${pkgs.curl}/bin/curl";
        jq = "${pkgs.jq}/bin/jq";
        subdomain = pii.hosts.${hostKey}.name;
        domain = config.infra.domain;
      in
      ''
        API_KEY=$(cat "${config.vaultix.secrets.porkbun-api-key.path}")
        SECRET_KEY=$(cat "${config.vaultix.secrets.porkbun-secret-key.path}")

        # Get current WAN IP from Porkbun's ping endpoint
        WAN_IP=$(${curl} -sf -X POST https://api.porkbun.com/api/json/v3/ping \
          -H 'Content-Type: application/json' \
          -d "{\"apikey\":\"$API_KEY\",\"secretapikey\":\"$SECRET_KEY\"}" \
          | ${jq} -r '.yourIp')

        if [ -z "$WAN_IP" ] || [ "$WAN_IP" = "null" ]; then
          echo "ERROR: Failed to detect WAN IP from Porkbun ping" >&2
          exit 1
        fi

        echo "Detected WAN IP: $WAN_IP"

        # Update/create the A record via editByNameType (idempotent — creates if missing)
        RESPONSE=$(${curl} -sf -X POST \
          "https://api.porkbun.com/api/json/v3/dns/editByNameType/${domain}/A/${subdomain}" \
          -H 'Content-Type: application/json' \
          -d "{\"apikey\":\"$API_KEY\",\"secretapikey\":\"$SECRET_KEY\",\"content\":\"$WAN_IP\",\"ttl\":\"600\"}")

        STATUS=$(echo "$RESPONSE" | ${jq} -r '.status')

        if [ "$STATUS" = "SUCCESS" ]; then
          echo "Updated ${subdomain}.${domain} A record to $WAN_IP"
        else
          # If editByNameType fails (record doesn't exist yet), try create
          echo "editByNameType failed, attempting create..."
          RESPONSE=$(${curl} -sf -X POST \
            "https://api.porkbun.com/api/json/v3/dns/create/${domain}" \
            -H 'Content-Type: application/json' \
            -d "{\"apikey\":\"$API_KEY\",\"secretapikey\":\"$SECRET_KEY\",\"type\":\"A\",\"name\":\"${subdomain}\",\"content\":\"$WAN_IP\",\"ttl\":\"600\"}")

          STATUS=$(echo "$RESPONSE" | ${jq} -r '.status')

          if [ "$STATUS" = "SUCCESS" ]; then
            echo "Created ${subdomain}.${domain} A record with $WAN_IP"
          else
            echo "ERROR: Failed to update/create DNS record: $RESPONSE" >&2
            exit 1
          fi
        fi
      '';
  };

  systemd.timers.porkbun-ddns = {
    description = "Timer for Porkbun DDNS update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Unit = "porkbun-ddns.service";
    };
  };
}
