{
  config,
  pkgs,
  pii,
  modulesPath,
  ...
}:
let
  hostPII = pii.hosts.cloud1;
in
{
  imports = [
    "${modulesPath}/virtualisation/azure-image.nix"
    ../../modules/infra.nix
    ../../secrets/ports.nix
    ../../modules/services/caddy.nix
    ../../modules/services/revaulter.nix
  ];
  nixpkgs.hostPlatform = "x86_64-linux";
  virtualisation.diskSize = 8192;
  time.timeZone = "America/Los_Angeles";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "${hostPII.name}";

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

  services.cloud-init.settings = {
    ssh_deletekeys = false;
    ssh_genkeytypes = [ ];
    cloud_init_modules = pkgs.lib.mkForce [
      "migrator"
      "seed_random"
      "bootcmd"
      "write-files"
      "growpart"
      "resizefs"
      "update_hostname"
      "resolv_conf"
      "ca-certs"
      "rsyslog"
    ];
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
  security.sudo.wheelNeedsPassword = false;

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

  infra.domain = hostPII.domain;

  system.stateVersion = "26.05";
}
