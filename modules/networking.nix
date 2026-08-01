{
  hostKey ? null,
  config,
  pii,
  lib,
  pkgs,
  ...
}:
lib.mkMerge [
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
          ipv4 = {
            method = "auto";
            route-metric = 3000;
            dhcp-client-id = "mac";
          };
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
  (lib.mkIf (hostKey == "homelab1") {
    # Create a bridge between two eth ports
    networking.networkmanager.ensureProfiles.profiles = {
      "br0" = {
        connection = {
          id = "br0";
          type = "bridge";
          interface-name = "br0";
          autoconnect = true;
        };
        bridge = {
          mac-address = pii.hosts.homelab1.mac;
        };
        ipv4 = {
          method = "manual";
          address1 = "${pii.hosts.homelab1.localIp}/24,${pii.router.localIp}";
          dns = "${pii.router.localIp};1.0.0.1;";
        };
        ipv6 = {
          method = "disabled";
        };
      };
      "br0-eno1" = {
        connection = {
          id = "br0-eno1";
          type = "ethernet";
          interface-name = "eno1";
          master = "br0";
          slave-type = "bridge";
          autoconnect = true;
        };
      };
      "br0-enp4s0" = {
        connection = {
          id = "br0-enp4s0";
          type = "ethernet";
          interface-name = "enp4s0";
          master = "br0";
          slave-type = "bridge";
          autoconnect = true;
        };
      };
    };

    networking.firewall.trustedInterfaces = [ "br0" ];
    # needed cuz packets from eno1 end up in br0 which is v sus for firewall
    networking.firewall.checkReversePath = "loose";
    networking.firewall.allowPing = true;

    networking.networkmanager.ensureProfiles.profiles = {
      # OLD: don't prioritize lan over wifi for ANY ethernet connection
      # TODO: Make this a config option
      eth-local = lib.mkIf false {
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
    # Flush the IP address assigned by systemd-networkd in initrd
    # so it doesn't conflict with the bridge (br0) routing.
    systemd.services."flush-initrd-ips" = {
      description = "Flush initrd IPs on physical interfaces";
      before = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "flush-ips" ''
          ${pkgs.iproute2}/bin/ip addr flush dev eno1 || true
          ${pkgs.iproute2}/bin/ip addr flush dev enp4s0 || true
        ''}";
      };
    };
  })
]
