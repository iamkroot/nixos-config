{
  lib,
  config,
  pkgs,
  pii,
  ...
}:
let
  hostPII = pii.hosts.sandbox1;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/networking.nix
    ../../modules/ports.nix
    ../../secrets/ports.nix
    ../../modules/services/atuin.nix
    ../../modules/services/jellyfin.nix
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # zfs
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev";
  services.zfs.trim.enable = true;
  networking.hostId = "${hostPII.netId}";
  networking.hostName = "${hostPII.name}";

  time.timeZone = "America/Los_Angeles";

  # services.displayManager.sddm.enable = true;
  # services.desktopManager.plasma6.enable = true;
  # services.displayManager.sddm.wayland.enable = true;
  # xdg.portal.enable = true;
  # services.qemuGuest.enable = true;
  # services.spice-vdagentd.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  vaultix = {
    settings.hostPubkey = "${hostPII.pubkey}";
    secrets = {
      "user-pwd" = {
        file = "${hostPII.secrets.user-pwd}";
      };
      "ssh-key" = {
        file = "${hostPII.secrets.ssh-key}";
      };
      "github-ssh-key" = {
        file = "${hostPII.secrets.github-ssh-key}";
        owner = "${pii.primaryUser}";
        mode = "0400";
      };
    };
    beforeUserborn = [ "user-pwd" ];
  };

  programs.zsh.enable = true;
  users.users."${pii.primaryUser}" = {
    isNormalUser = true;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "${pii.userPubkey}"
    ];
    hashedPasswordFile = config.vaultix.secrets."user-pwd".path;
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      "${pii.userPubkey}"
    ];
    shell = pkgs.zsh;
    hashedPasswordFile = config.vaultix.secrets."user-pwd".path;
  };
  # users.mutableUsers = false;
  services.userborn.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    helix
    wget
    wl-clipboard
    bat
    eza
    ripgrep
    dust
    fd
    aria2
    zsh
  ];
  # FIXME: Should ensure the derived sub-domains for services are correct
  infra.domain = "localhost";
  # atuin is hosted on this machine
  infra.services.hostnames.atuin = hostPII.localIp;

  disko.zfs = {
    enable = true;
    settings = {
      logLevel = "trace";
      ignoredDatasets = ["zroot/root"];
      ignoredProperties = ["keylocation" "nixos:shutdown-time"];
    };
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  system.stateVersion = "26.05";
}
