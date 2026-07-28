{
  config,
  pkgs,
  myUtils,
  ...
}:

{
  imports = [ (myUtils.mkCaddyModule "whoami" { authelia = true; }) ];

  virtualisation.oci-containers.containers."whoami" = {
    image = "containous/whoami";
    ports = [ "127.0.0.1:${toString config.infra.services.ports.whoami}:80" ];
  };
}
