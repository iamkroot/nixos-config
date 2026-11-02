{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.infra.services.ports.mosquitto;
  hassPwd = config.vaultix.secrets."mosquitto/password".path;
  onstarPwd = config.vaultix.secrets."mosquitto/onstar_password".path;
in
{
  vaultix.secrets."mosquitto/password" = { };
  vaultix.secrets."mosquitto/onstar_password" = { };

  services.mosquitto = {
    enable = true;
    persistence = true;
    listeners = [
      {
        inherit port;
        settings = {
          bind_interface = "podman0";
          allow_anonymous = false;
        };
        users = {
          hass = {
            acl = [ "readwrite #" ];
            passwordFile = hassPwd;
          };
          onstar = {
            acl = [
              "write homeassistant/#"
              "readwrite homeassistant/+/command/#"
              "read homeassistant/status"
              "readwrite onstar2mqtt/#"
            ];
            passwordFile = onstarPwd;
          };
        };
      }
    ];
  };

  systemd.services.mosquitto = {
    after = [
      "vaultix-activate.service"
      "sys-subsystem-net-devices-podman0.device"
    ];
    wants = [
      "sys-subsystem-net-devices-podman0.device"
    ];
    requires = [
      "vaultix-activate.service"
    ];
  };

  networking.firewall.interfaces."podman0".allowedTCPPorts = [
    port
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/mosquitto 0700 mosquitto mosquitto -"
  ];
}
