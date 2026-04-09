{ lib, ... }:
{
  mkPortOption =
    defaultPort: description:
    lib.mkOption {
      type = lib.types.port;
      default = defaultPort;
      description = description;
    };
}
