{
  config,
  myUtils,
  pkgs,
  ...
}:
let
  port = config.infra.services.ports.argus;

  initialConfig = pkgs.writeText "argus-initial-config.yml" ''
    settings:
      data:
        database_file: "/app/data/argus.db"
      web:
        listen_host: "0.0.0.0"
        listen_port: 8080

    defaults:
      service:
        options:
          interval: "30m"
          semantic_versioning: true

    service: {}
  '';
in
{
  imports = [
    (myUtils.mkCaddyModule "argus" {
      authelia = true;
    })
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/argus 0755 root root -"
    "d /var/lib/argus/data 0755 root root -"
    "C /var/lib/argus/config.yml 0644 root root - ${initialConfig}"
  ];

  virtualisation.oci-containers.containers."argus" = {
    image = myUtils.mkImage config.infra.versions.argus;
    ports = [ "127.0.0.1:${toString port}:8080" ];
    volumes = [
      "/var/lib/argus/config.yml:/app/config.yml"
      "/var/lib/argus/data:/app/data"
    ];
  };

  systemd.services.podman-argus = {
    after = [ "disko-zfs.service" ];
    preStart = ''
      mkdir -p /var/lib/argus/data
      if [ ! -f /var/lib/argus/config.yml ]; then
        cp ${initialConfig} /var/lib/argus/config.yml
        chmod 0644 /var/lib/argus/config.yml
      fi
    '';
  };
}
