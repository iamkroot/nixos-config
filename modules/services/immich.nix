{
  config,
  myUtils,
  pii,
  pkgs,
  ...
}:
let
  immichVersion = "v3.2.0-rc.3";
  envFile = config.vaultix.templates."immich.env".path;
in
{
  imports = [
    (myUtils.mkCaddyModule "immich" { authelia = true; })
  ];

  myAuthelia.oidcClients = [
    (myUtils.mkAutheliaOIDC pii "immich" {
      redirect_uris = [
        "https://${config.infra.services.hostnames.immich}/auth/login"
        "https://${config.infra.services.hostnames.immich}/user-settings"
        "app.immich:///oauth-callback"
      ];
    })
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
      image = "docker.io/valkey/valkey:9@sha256:4963247afc4cd33c7d3b2d2816b9f7f8eeebab148d29056c2ca4d7cbc966f2d9";
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
      extraOptions = [
        "--network=immich"
        # needed to get sso working
        "--add-host=${config.infra.services.hostnames.auth}:host-gateway"
      ];
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
        "/media/photos:/data"
        "/var/lib/immich/thumbs:/data/thumbs"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/immich/thumbs 0755 root root - -"
  ];

  systemd.services."podman-immich-postgres".after = [ "create-immich-network.service" ];
  systemd.services."podman-immich-redis".after = [ "create-immich-network.service" ];
  systemd.services."podman-immich-machine-learning".after = [ "create-immich-network.service" ];
  systemd.services."podman-immich-server" =
    let
      ssd2 = pii.storage.ssd2;
    in
    {
      after = [
        "create-immich-network.service"
        "load-${ssd2.name}-keys.service"
      ];
      requires = [
        "load-${ssd2.name}-keys.service"
      ];
      bindsTo = [
        "load-${ssd2.name}-keys.service"
      ];
    };
}
