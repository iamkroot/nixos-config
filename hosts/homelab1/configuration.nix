{
  config,
  pkgs,
  pii,
  ...
}:
let
  hostPII = pii.hosts.homelab1;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/networking.nix
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

  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  xdg.portal.enable = true;

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
      "github-ssh-key" = {
        file = "${hostPII.secrets.github-ssh-key}";
        path = "/home/${pii.primaryUser}/.ssh/github_ed25519";
        owner = "${pii.primaryUser}";
        mode = "0400";
      };
      "ssh-key" = {
        file = "${hostPII.secrets.ssh-key}";
      };
    };
    beforeUserborn = [ "user-pwd" ];
  };

  programs.zsh.enable = true;
  users.users."${pii.primaryUser}" = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "${pii.userPubkey}"
    ];
    hashedPasswordFile = config.vaultix.secrets."user-pwd".path;
  };

  users.users.root = {
    shell = pkgs.zsh;
    hashedPasswordFile = config.vaultix.secrets."user-pwd".path;
  };
  users.mutableUsers = false;

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

  services.openssh = {
    enable = true;
  };
  system.stateVersion = "26.05";
}
