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
}
