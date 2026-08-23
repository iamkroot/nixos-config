{
  config,
  pkgs,
  ...
}:

{
  services.nats = {
    enable = true;
    jetstream = true;
    port = config.infra.services.ports.nats;
    settings = {
      http_port = config.infra.services.ports.nats_http;
      jetstream = {
        max_mem = 1073741824; # 1GB in bytes
        max_file = 21474836480; # 20GB in bytes
      };
    };
  };

  # CLI utilities for stream management and live metrics
  environment.systemPackages = [
    pkgs.natscli
    pkgs.nats-top
  ];
}
