{ lib, ... }:
{
  mkPortOption =
    defaultPort: description:
    lib.mkOption {
      type = lib.types.port;
      default = defaultPort;
      description = description;
    };
  # for LDAP stuff
  domainToBaseDN =
    domain: lib.concatStringsSep "," (map (part: "dc=${part}") (lib.splitString "." domain));

  # use via `imports = [(mkCaddyModule "foobar")]`
  mkCaddyModule =
    name:
    {
      authelia ? false,
      extraHostConfig ? { },
      portKey ? name,
    }:
    { config, ... }:
    let
      hostname = config.infra.services.hostnames."${name}";
      port = config.infra.services.ports."${portKey}";
    in
    {
      services.caddy.virtualHosts."${hostname}" = lib.mkMerge [
        {
          useACMEHost = config.infra.domain;
          extraConfig = ''
            ${if authelia then "import authelia" else ""}
            reverse_proxy 127.0.0.1:${toString port}
          '';

          logFormat = lib.mkDefault ''
            output file /var/log/caddy/access-${hostname}.log {
              roll_size 50mb
              roll_keep 5
            }
          '';
        }
        extraHostConfig
      ];
    };
}
