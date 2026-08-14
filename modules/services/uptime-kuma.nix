{
  config,
  myUtils,
  ...
}:
let
  kumaPort = config.infra.services.ports.uptime-kuma;
in
{
  imports = [
    (myUtils.mkCaddyModule "uptime-kuma" { authelia = false; })
  ];

  # Native Uptime Kuma System Service
  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = toString kumaPort;
    };
  };
}
