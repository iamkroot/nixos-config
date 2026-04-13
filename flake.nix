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

    disko-zfs = {
      url = "github:numtide/disko-zfs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    zsh-patina = {
      url = "github:michel-kraemer/zsh-patina";
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
      disko-zfs,
      ...
    }@inputs:
    let
      pii = import ./secrets/pii.nix;
      myUtils = import ./modules/utils.nix { inherit (nixpkgs) lib; };
    in
    {
      nixosConfigurations = {
        "${pii.hosts.sandbox1.name}" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs pii myUtils; };
          modules = [
            disko.nixosModules.disko
            disko-zfs.nixosModules.default
            vaultix.nixosModules.default

            ./hosts/sandbox1/configuration.nix

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs pii; };
              home-manager.users."${pii.primaryUser}" = import ./home/user1.nix;
              home-manager.users.root = import ./home/root.nix;
            }
          ];
        };
        "${pii.hosts.homelab1.name}" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs pii myUtils; };
          modules = [
            disko.nixosModules.disko
            disko-zfs.nixosModules.default
            vaultix.nixosModules.default
            ./hosts/homelab1/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs pii; };
              home-manager.users."${pii.primaryUser}" = import ./home/user1.nix;
              home-manager.users.root = import ./home/root.nix;
            }
          ];
        };
        "${pii.hosts.live.name}" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs pii; };
          modules = [
            vaultix.nixosModules.default
            ./hosts/live/iso.nix
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
