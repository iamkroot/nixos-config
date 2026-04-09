{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers."whoami" = {
    image = "containous/whoami";
    ports = [ "127.0.0.1:${toString config.infra.services.ports.whoami}:80" ];
  };
  services.caddy.virtualHosts."${config.infra.services.hostnames.whoami}" = {
    extraConfig = ''
      import authelia
      reverse_proxy 127.0.0.1:${toString config.infra.services.ports.whoami}
    '';
    logFormat = ''
      output file /var/log/caddy/access-${config.infra.services.hostnames.whoami}.log {
        roll_size 50mb
        roll_keep 5
      }
    '';
  };
}
