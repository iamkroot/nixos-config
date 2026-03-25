{ lib, pii, ... }:

{
  options.infra.services.ports = {
    atuin = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Port for the Atuin sync server";
    };

    caddy = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "HTTPS port for Caddy reverse proxy";
    };
  };
}
