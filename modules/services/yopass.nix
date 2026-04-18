{
  config,
  lib,
  pii,
  myUtils,
  pkgs,
  ...
}:
let
  port = config.infra.services.ports.yopass;
in
{
  imports = [
    (myUtils.mkCaddyModule "yopass" { authelia = true; })
  ];
  # Create an internal network just for Yopass and its database
  systemd.services.podman-network-yopass-net = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.podman}/bin/podman network create --ignore --disable-dns --subnet 10.99.99.0/24 yopass-net";
    };
  };

  virtualisation.oci-containers.containers = {
    yopass-memcached = {
      image = "memcached:alpine";
      # Assign a specific static IP within our custom subnet
      extraOptions = [
        "--network=yopass-net"
        "--ip=10.99.99.10"
      ];
    };
    yopass = {
      image = "jhaals/yopass:latest";
      ports = [ "127.0.0.1:${toString port}:${toString port}" ];
      environment = {
        MEMCACHED = "10.99.99.10:11211";
      };
      extraOptions = [ "--network=yopass-net" ];
      dependsOn = [ "yopass-memcached" ];
    };
  };

  # Ensure the internal network exists before Yopass starts
  systemd.services."podman-yopass-memcached".requires = [ "podman-network-yopass-net.service" ];
  systemd.services."podman-yopass-memcached".after = [ "podman-network-yopass-net.service" ];
  systemd.services."podman-yopass".requires = [ "podman-network-yopass-net.service" ];
  systemd.services."podman-yopass".after = [ "podman-network-yopass-net.service" ];
}
