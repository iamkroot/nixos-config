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
  ];

  # networking.hostId = "${hostPII.netId}";
  networking.hostName = "${hostPII.name}";
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
    };
    beforeUserborn = [ "user-pwd" ];
  };
}
