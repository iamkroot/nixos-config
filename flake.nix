{
  description = "Homelab & Workstation Infrastructure";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vaultix = {
      url = "github:milieuim/vaultix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      vaultix,
      disko,
      ...
    }@inputs:
    let
      pii = import ./secrets/pii.nix;
    in
    {
      nixosConfigurations = {
        "${pii.hosts.sandbox1.name}" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs pii; };
          modules = [
            disko.nixosModules.disko
            vaultix.nixosModules.default

            ./hosts/sandbox1/configuration.nix

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit pii; };
              home-manager.users."${pii.primaryUser}" = import ./home/user1.nix;
            }
          ];
        };
        "${pii.hosts.homelab1.name}" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs pii; };
          modules = [
            disko.nixosModules.disko
            vaultix.nixosModules.default
            ./hosts/homelab1/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit pii; };
              home-manager.users."${pii.primaryUser}" = import ./home/user1.nix;
            }
          ];
        };
      };
      vaultix = vaultix.configure {
        cache = "./secrets/cache";
        identity = "${pii.ageIdentity}";
        nodes = self.nixosConfigurations;
      };
    };
}
