{
  config,
  pkgs,
  pii,
  ...
}:

{
  hardware.enableRedistributableFirmware = true;
  boot.initrd.availableKernelModules = [ "r8169" ];
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.network = {
    enable = true;

    networks."10-initrd-dhcp" = {
      # Match any ethernet interface name (enp3s0, eno1, etc.)
      matchConfig.Name = "en*";

      # Explicitly enable IPv4 DHCP
      networkConfig.DHCP = "ipv4";

      # Don't halt the boot process if the cable is unplugged
      linkConfig.RequiredForOnline = "no";
    };
  };
  # Configure initrd networking and SSH
  boot.initrd.network = {
    enable = true;

    ssh = {
      enable = true;
      # Use an alternate port to prevent known_hosts conflicts with the main OS
      port = 22222;

      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];

      authorizedKeys = [ pii.userPubkey ];
    };
  };
}
