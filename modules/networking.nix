{
  host,
  config,
  pii,
  ...
}:
{
  networking.networkmanager = {
    enable = true;
    ensureProfiles.profiles = {
      "${pii.networks.wifi1.name}" = {
        connection = {
          id = "${pii.networks.wifi1.name}";
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          ssid = "${pii.networks.wifi1.name}";
          mode = "infrastructure";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$wifi1";
        };
        ipv4.method = "auto";
      };
    };
    ensureProfiles.environmentFiles = [
      config.vaultix.templates.network-secrets.path
    ];
  };
  vaultix.secrets."wifi1-pwd" = {
    file = "${pii.networks.wifi1.pwd}";
  };
  vaultix.templates.network-secrets.content = "wifi1=${config.vaultix.placeholder."wifi1-pwd"}";
  # don't prioritize lan over wifi
  networking.networkmanager.ensureProfiles.profiles = {
    eth-local = {
      connection = {
        id = "eth-local";
        type = "ethernet";
        interface-name = "enp*"; # You might need the exact name here, like enp3s0
        # Don't wait for this connection to finish boot
        wait-device-timeout = 1;
      };
      ipv4 = {
        method = "auto";
        route-metric = 2000;
        # Tell NM never to use this as the default route for internet
        never-default = true;
      };
    };
  };
}
