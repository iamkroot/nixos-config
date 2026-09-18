{
  config,
  pkgs,
  myUtils,
  ...
}:

{
  imports = [ (myUtils.mkCaddyModule "whoami" { authelia = true; }) ];

  virtualisation.oci-containers.containers."whoami" = {
    image = "docker.io/containous/whoami:v1.5.0@sha256:7d6a3c8f91470a23ef380320609ee6e69ac68d20bc804f3a1c6065fb56cfa34e";
    ports = [ "127.0.0.1:${toString config.infra.services.ports.whoami}:80" ];
  };
}
