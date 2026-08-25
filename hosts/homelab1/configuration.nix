{
  config,
  pkgs,
  pii,
  lib,
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
    ../../modules/infra.nix
    ../../modules/services/atuin.nix
    ../../modules/services/caddy.nix
    ../../modules/services/crowdsec.nix
    ../../modules/services/gaming.nix
    ../../modules/storage
    ../../modules/storage/nfs.nix
    ../../modules/initrd.nix
    ../../modules/kde.nix
    ../../modules/revaulter-cli.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # zswap
  boot.kernelParams = [
    "zswap.enabled=0"
    "zswap.compressor=zstd"
    "zswap.max_pool_percent=20"
    "zswap.zpool=zsmalloc"
    # Limit ZFS ARC to 4GB
    "zfs.zfs_arc_max=4294967296"

    "consoleblank=600"
  ];

  # zfs
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id";
  services.zfs.trim.enable = true;
  networking.hostId = "${hostPII.netId}";
  networking.hostName = "${hostPII.name}";

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = [ "zroot" ];
  };

  time.timeZone = "America/Los_Angeles";
  services.timesyncd.enable = false;
  services.chrony.enable = true;

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
    };
    beforeUserborn = [ "user-pwd" ];
  };

  programs.zsh.enable = true;
  users.users."${pii.primaryUser}" = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "i2c"
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

  hardware.i2c.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    aria2
    bat
    btop
    ddcutil
    dust
    dysk
    eza
    fd
    git
    hdparm
    helix
    i2c-tools
    inetutils
    ripgrep
    tmux
    wget
    wl-clipboard
    zsh
  ];

  # needed to get sso working for jellyfin
  networking.hosts = {
    "127.0.0.1" = [
      config.infra.services.hostnames.jellyfin
      config.infra.services.hostnames.auth
      config.infra.services.hostnames.ldap
    ];
  };

  # DNS-01 ACME is handled by Caddy globally via Porkbun plugin
  security.acme = {
    acceptTerms = true;
    defaults.email = pii.primaryEmail;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
    };
  };

  services.eternal-terminal = {
    enable = true;
    port = config.infra.services.ports.et;
  };
  networking.firewall.allowedTCPPorts = [ config.infra.services.ports.et ];

  system.stateVersion = "26.05";
}
