{
  config,
  pkgs,
  myUtils,
  ...
}:
let
  mqttPort = config.infra.services.ports.mosquitto;
  tokenSecret = config.vaultix.secrets."onstar/tokens".path;
  targetToken = "/var/lib/onstar2mqtt/tokens/microsoft_tokens.json";
in
{
  vaultix.secrets."onstar/tokens" = { };
  vaultix.secrets."onstar/env" = { };

  virtualisation.oci-containers.containers."onstar2mqtt" = {
    image = myUtils.mkImage config.infra.versions.onstar2mqtt;
    environment = {
      MQTT_HOST = "host.containers.internal";
      MQTT_PORT = toString mqttPort;
      TOKEN_LOCATION = "/app/tokens";
      UNIT_CACHE_DIR = "/app/data";
      ONSTAR_STATE_CACHE = "true";
      TZ = "America/Los_Angeles";
    };
    environmentFiles = [
      config.vaultix.secrets."onstar/env".path
    ];
    volumes = [
      "/var/lib/onstar2mqtt/tokens:/app/tokens:rw"
      "/var/lib/onstar2mqtt/data:/app/data:rw"
      "/etc/localtime:/etc/localtime:ro"
    ];
    extraOptions = [
      "--add-host=host.containers.internal:host-gateway"
    ];
  };

  systemd.services."podman-onstar2mqtt" = {
    after = [
      "mosquitto.service"
      "vaultix-activate.service"
    ];
    wants = [
      "mosquitto.service"
    ];
    requires = [
      "vaultix-activate.service"
    ];
    preStart = ''
      mkdir -p /var/lib/onstar2mqtt/tokens /var/lib/onstar2mqtt/data
      chmod 700 /var/lib/onstar2mqtt/tokens

      SECRET_HASH="$(${pkgs.coreutils}/bin/sha256sum ${tokenSecret} | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
      HASH_FILE="/var/lib/onstar2mqtt/.tokens_hash"

      if [ ! -f ${targetToken} ] || [ ! -f "$HASH_FILE" ] || [ "$SECRET_HASH" != "$(${pkgs.coreutils}/bin/cat "$HASH_FILE")" ]; then
        cp ${tokenSecret} ${targetToken}
        chmod 600 ${targetToken}
        echo "$SECRET_HASH" > "$HASH_FILE"
      fi
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/onstar2mqtt 0755 root root -"
    "d /var/lib/onstar2mqtt/tokens 0700 root root -"
    "d /var/lib/onstar2mqtt/data 0755 root root -"
  ];
}
