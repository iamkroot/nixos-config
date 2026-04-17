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
    ../../modules/ports.nix
    ../../secrets/ports.nix
    ../../modules/services/aria2.nix
    ../../modules/services/atuin.nix
    ../../modules/services/jellyfin.nix
    ../../modules/services/shoko.nix
    ../../modules/services/caddy.nix
    ../../modules/services/crowdsec.nix
    ../../modules/services/duckdns.nix
    ../../modules/services/lldap.nix
    ../../modules/services/authelia.nix
    ../../modules/services/whoami.nix
    ../../modules/services/adguard.nix
    ../../modules/services/redlib.nix
    ../../modules/storage
    ../../modules/initrd.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # zswap
  boot.kernelParams = [
    "zswap.enabled=0"
    "zswap.compressor=zstd"
    "zswap.max_pool_percent=20"
    "zswap.zpool=zsmalloc"
    # Limit ZFS ARC to 8GB
    "zfs.zfs_arc_max=8589934592"
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
    btop
    dust
    dysk
    eza
    fd
    git
    helix
    inetutils
    ripgrep
    tmux
    wget
    wl-clipboard
    zsh
  ];

  infra.domain = hostPII.domain;
  # needed to get sso working for jellyfin
  networking.hosts = {
    "127.0.0.1" = [
      config.infra.services.hostnames.jellyfin
      config.infra.services.hostnames.auth
      config.infra.services.hostnames.ldap
    ];
  };

  # needed for adguard DoT
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
