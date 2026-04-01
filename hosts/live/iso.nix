# inspired by https://michael.stapelberg.ch/posts/2025-06-01-nixos-installation-declarative/

{
  config,
  pkgs,
  pii,
  modulesPath,
  inputs,
  ...
}:
let
  hostPII = pii.hosts.live;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
    ../../modules/networking.nix
    # ../../modules/zsh.nix
    # ../../modules/cli-tools.nix
  ];

  networking.hostId = "${hostPII.netId}";
  networking.hostName = "${hostPII.name}";

  security.sudo.wheelNeedsPassword = false;
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
    packages = with pkgs; [ ];
  };

  users.users.root = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "${pii.userPubkey}"
    ];
  };
  services.userborn.enable = true;

  vaultix = {
    settings.hostPubkey = "${hostPII.pubkey}";
    secrets = {
      "user-pwd" = {
        file = "${hostPII.secrets.user-pwd}";
      };
      "github-ssh-key" = {
        file = "${hostPII.secrets.github-ssh-key}";
        owner = "${pii.primaryUser}";
        mode = "0400";
      };
      "ssh-key" = {
        file = "${hostPII.secrets.ssh-key}";
      };
    };
    beforeUserborn = [ "user-pwd" ];
  };
  systemd.services.vaultix-activate-before-user.preStart = ''
    # Manually build the directory if the system hasn't yet
    mkdir -p /etc/ssh

    # Copy the key directly from the Nix store into the /etc/ssh folder
    cat ${builtins.toFile "iso-vaultix-key" (builtins.readFile ../../secrets/live-ssh-key)} > /etc/ssh/ssh_host_ed25519_key

    # Lock down the permissions so SSH/Vaultix doesn't reject it
    chmod 600 /etc/ssh/ssh_host_ed25519_key
  '';
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    aria2
    bat
    btop
    curl
    dust
    dysk
    eza
    fd
    git
    helix
    lshw
    ripgrep
    rsync
    wget
    zsh
  ];

  programs.zsh.enable = true;
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
    };
  };

  system.stateVersion = "26.05";
}
