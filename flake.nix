{
  description = "Homelab & Workstation Infrastructure";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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

    dashboard-icons = {
      url = "github:homarr-labs/dashboard-icons";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      plasma-manager,
      vaultix,
      disko,
      disko-zfs,
      ...
    }@inputs:
    let
      pii = import ./secrets/pii.nix;
      services = import ./secrets/services.nix;
      myUtils = import ./modules/utils.nix {
        inherit (nixpkgs) lib;
      };
      serviceModulesForHost =
        hostKey:
        let
          hostServices = nixpkgs.lib.filterAttrs (_: s: s.host == hostKey) services;
          moduleNames = nixpkgs.lib.mapAttrsToList (name: s: s.module or name) hostServices;
          uniqueModules = nixpkgs.lib.unique (nixpkgs.lib.filter (m: m != null) moduleNames);
        in
        map (m: ./modules/services/${m}.nix) uniqueModules;
    in
    {
      nixosConfigurations = {
        "${pii.hosts.sandbox1.name}" = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pii
              myUtils
              services
              ;
            hostKey = "sandbox1";
          };
          modules = [
            disko.nixosModules.disko
            disko-zfs.nixosModules.default
            vaultix.nixosModules.default

            ./hosts/sandbox1/configuration.nix

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.sharedModules = [ plasma-manager.homeModules.plasma-manager ];
              home-manager.extraSpecialArgs = { inherit inputs pii services; };
              home-manager.users."${pii.primaryUser}" = import ./home/user1.nix;
              home-manager.users.root = import ./home/root.nix;
            }
          ]
          ++ serviceModulesForHost "sandbox1";
        };
        "${pii.hosts.homelab1.name}" = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pii
              myUtils
              services
              ;
            hostKey = "homelab1";
          };
          modules = [
            disko.nixosModules.disko
            disko-zfs.nixosModules.default
            vaultix.nixosModules.default
            ./hosts/homelab1/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.sharedModules = [ plasma-manager.homeModules.plasma-manager ];
              home-manager.extraSpecialArgs = { inherit inputs pii services; };
              home-manager.users."${pii.primaryUser}" = import ./home/user1.nix;
              home-manager.users.root = import ./home/root.nix;
            }
          ]
          ++ serviceModulesForHost "homelab1";
        };
        "${pii.hosts.cloud1.name}" = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pii
              myUtils
              services
              ;
            hostKey = "cloud1";
          };
          modules = [
            vaultix.nixosModules.default
            ./hosts/cloud1/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.sharedModules = [ plasma-manager.homeModules.plasma-manager ];
              home-manager.extraSpecialArgs = { inherit inputs pii services; };
              home-manager.users."${pii.primaryUser}" = import ./home/user1.nix;
              home-manager.users.root = import ./home/root.nix;
            }
          ]
          ++ serviceModulesForHost "cloud1";
        };
        "${pii.hosts.live.name}" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs pii services;
            hostKey = "live";
          };
          modules = [
            vaultix.nixosModules.default
            ./hosts/live/iso.nix
          ]
          ++ serviceModulesForHost "live";
        };
      };
      vaultix = vaultix.configure {
        cache = "./secrets/cache";
        identity = "${pii.ageIdentity}";
        nodes = self.nixosConfigurations;
      };
    };
}
