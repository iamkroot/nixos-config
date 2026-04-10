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
  # don't prioritize lan over wifi for ANY ethernet connection
  networking.networkmanager.ensureProfiles.profiles = {
    eth-local = {
      connection = {
        id = "eth-local";
        type = "ethernet";
        wait-device-timeout = 1;
        # Allow this profile to be active on multiple ports simultaneously
        multi-connect = 3;
      };
      match = {
        # This covers standard Linux 'eth' names and predictable 'en' names (eno, enp, ens)
        "interface-name" = "en*;eth*";
      };
      ipv4 = {
        method = "auto";
        route-metric = 2000;
        never-default = true;
      };
    };
  };
}
