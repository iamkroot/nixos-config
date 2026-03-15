{
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
  ];

  # networking.hostId = "${hostPII.netId}";
  networking.hostName = "${hostPII.name}";
  vaultix = {
    settings.hostPubkey = "${hostPII.pubkey}";
    secrets."user-pwd" = {
      file = "${hostPII.secrets.user-pwd}";
    };
    beforeUserborn = [ "user-pwd" ];
  };
}
