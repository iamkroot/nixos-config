{ ... }:
{
  imports = [
    ./base.nix
    ./repository-service.nix
    ./policy-service.nix
    ./snapshot-service.nix
    ./web-service.nix
  ];
}
