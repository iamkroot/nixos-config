{
  config,
  myUtils,
  pkgs,
  ...
}:
let
  immichVersion = "v2.7.5";
  envFile = config.vaultix.templates."immich.env".path;
in
{
  imports = [
    (myUtils.mkCaddyModule "immich" { authelia = true; })
  ];
  vaultix.secrets."immich/db_pwd" = { };
  vaultix.templates."immich.env" = {
    content = ''
      POSTGRES_USER=immich
      POSTGRES_DB=immich
      POSTGRES_PASSWORD=${config.vaultix.placeholder."immich/db_pwd"}

      DB_USERNAME=immich
      DB_DATABASE_NAME=immich
      DB_PASSWORD=${config.vaultix.placeholder."immich/db_pwd"}
    '';
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.oci-containers.backend = "podman";

  # Create a dedicated Podman network for Immich so containers can talk to each other
  systemd.services.create-immich-network = {
    description = "Create Podman network for Immich";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists immich || ${pkgs.podman}/bin/podman network create immich
    '';
  };

  # Define the OCI Containers
  virtualisation.oci-containers.containers = {
    immich-postgres = {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
      extraOptions = [
        "--network=immich"
        "--shm-size=128m"
      ];
      environmentFiles = [ envFile ];
      environment = {
        POSTGRES_INITDB_ARGS = "--data-checksums";
      };
      volumes = [
        "/var/lib/immich/postgres:/var/lib/postgresql/data"
      ];
    };

    immich-redis = {
      image = "docker.io/valkey/valkey:9@sha256:3b55fbaa0cd93cf0d9d961f405e4dfcc70efe325e2d84da207a0a8e6d8fde4f9";
      extraOptions = [ "--network=immich" ];
    };

    immich-machine-learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:${immichVersion}";
      extraOptions = [ "--network=immich" ];
      environmentFiles = [ envFile ];
      volumes = [
        "/var/lib/immich/model-cache:/cache"
      ];
    };

    immich-server = {
      image = "ghcr.io/immich-app/immich-server:${immichVersion}";
      extraOptions = [ "--network=immich" ];
      ports = [ "${toString config.infra.services.ports.immich}:2283" ];
      dependsOn = [
        "immich-postgres"
        "immich-redis"
      ];
      environmentFiles = [ envFile ];
      environment = {
        DB_HOSTNAME = "immich-postgres";
        REDIS_HOSTNAME = "immich-redis";
        IMMICH_MACHINE_LEARNING_URL = "http://immich-machine-learning:3003";
      };
      volumes = [
        "/mnt/immich_ssd:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };
  };

  systemd.services."podman-immich-postgres".after = [ "create-immich-network.service" ];
  systemd.services."podman-immich-redis".after = [ "create-immich-network.service" ];
  systemd.services."podman-immich-machine-learning".after = [ "create-immich-network.service" ];
  systemd.services."podman-immich-server".after = [ "create-immich-network.service" ];
}
