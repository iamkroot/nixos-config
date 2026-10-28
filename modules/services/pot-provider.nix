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
    })
  ];

  virtualisation.oci-containers.containers."pot-provider" = {
    image = myUtils.mkImage config.infra.versions.pot-provider;
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
