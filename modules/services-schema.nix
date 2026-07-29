{ lib, ... }:
let
  t = lib.types;
in
{
  options.myServices = lib.mkOption {
    description = "Homelab services configuration schema";
    type = t.attrsOf (
      t.submodule (
        { name, config, ... }: {
          options = {
            enable = lib.mkOption {
              type = t.bool;
              default = true;
            };
            port = lib.mkOption {
              type = t.port;
              default = 0;
            };
            host = lib.mkOption { type = t.str; };
            module = lib.mkOption {
              type = t.nullOr t.str;
              default = name;
            };
            subdomain = lib.mkOption {
              type = t.nullOr t.str;
              default = name;
            };
            dns = lib.mkOption {
              type = t.bool;
              default = true;
            };
            extraPorts = lib.mkOption {
              type = t.attrsOf t.port;
              default = { };
            };
            catalog = {
              enable = lib.mkOption {
                type = t.bool;
                default = true;
              };
              roles = lib.mkOption {
                type = t.attrsOf t.str;
                default = { };
              };
            };
          };
        }
      )
    );
  };
  config.myServices = import ../secrets/services.nix;
}
