# YT-DLP PoT provider
{
  config,
  myUtils,
  ...
}:
let
  port = config.infra.services.ports.pot-provider;
in
{
  imports = [
    (myUtils.mkCaddyModule "pot-provider" {
      authelia = false;
      meshOnly = true;
    })
  ];

  virtualisation.oci-containers.containers."pot-provider" = {
    image = "docker.io/brainicism/bgutil-ytdlp-pot-provider:latest";
    ports = [ "127.0.0.1:${toString port}:4416" ];

    environment = {
      PORT = "4416";
      HOST = "0.0.0.0";
    };

    extraOptions = [
      "--dns=1.1.1.1"
      "--dns=1.0.0.1"
    ];
  };
}
