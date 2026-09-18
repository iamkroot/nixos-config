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
    image = "docker.io/brainicism/bgutil-ytdlp-pot-provider:latest@sha256:ed86b6fdd5e430ddd7c8ce1adb55e1ab54db7c7dbc1bcbf3a82454a85b971164";
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
