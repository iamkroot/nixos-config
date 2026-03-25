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
    ../../modules/ports.nix
    ../../secrets/ports.nix
    ../../modules/services/atuin.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
    "vm.swappiness" = 10; # Only swap when memory is 90% full
  };

  # zfs
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id";
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
        # path = "/home/${pii.primaryUser}/.ssh/github_ed25519";
        owner = "${pii.primaryUser}";
        mode = "0400";
      };
      "ssh-key" = {
        file = "${hostPII.secrets.ssh-key}";
      };
      "das1-dataset1-key" = {
        file = "${pii.storage.das1.dataset1.key}";
        path = "${pii.storage.das1.dataset1.keypath}";
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
    openssh.authorizedKeys.keys = [
      "${pii.userPubkey}"
    ];
    hashedPasswordFile = config.vaultix.secrets."user-pwd".path;
  };
  users.mutableUsers = false;

  services.userborn.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    aria2
    bat
    dust
    dysk
    eza
    fd
    git
    helix
    ripgrep
    wget
    wl-clipboard
    zsh
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
    };
  };
  system.stateVersion = "26.05";
}
