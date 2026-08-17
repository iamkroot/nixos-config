{
  config,
  pii,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "headscale" { authelia = false; })
  ];

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = config.infra.services.ports.headscale;
    settings = {
      server_url = "https://${config.infra.services.hostnames.headscale}";
      dns = {
        magic_dns = true;
        base_domain = "mesh.${config.infra.domain}";
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
      # Keep metrics strictly on localhost
      metrics_listen_addr = "127.0.0.1:${toString config.infra.services.ports.headscaleMetrics}";
      # Define the IP pool for the mesh
      ip_prefixes = [
        pii.networks.mesh.subnet
        pii.networks.mesh.subnetV6
      ];
    };
  };
}
