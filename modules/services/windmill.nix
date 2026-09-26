{
  config,
  lib,
  myUtils,
  pkgs,
  ...
}:
let
  wmVersion = "1.818.0";
  wmImage = "ghcr.io/windmill-labs/windmill:${wmVersion}";
  extraImage = "ghcr.io/windmill-labs/windmill-extra:${wmVersion}";
  postgresImage = "docker.io/library/postgres:18";

  serverPort = config.infra.services.ports.windmill;
  extraPort = config.infra.services.ports.windmill_extra;
  envFile = config.vaultix.templates."windmill.env".path;

  allWindmillContainers = [
    "podman-windmill-postgres"
    "podman-windmill-server"
    "podman-windmill-worker"
    "podman-windmill-worker-native"
    "podman-windmill-extra"
  ];
in
{
  imports = [
    (myUtils.mkCaddyModule "windmill" {
      authelia = false;
      meshOnly = true; # Restrict to LAN and Tailscale mesh
      extraHostConfig = {
        extraConfig = ''
          # Extra services: LSP, Multiplayer, Debugger (WebSocket gateway)
          @extra path /ws/* /ws_mp/* /ws_debug/*
          handle @extra {
            reverse_proxy 127.0.0.1:${toString extraPort}
          }

          # Default: Windmill web UI and HTTP API
          handle {
            reverse_proxy 127.0.0.1:${toString serverPort}
          }
        '';
      };
    })
  ];

  vaultix.secrets."windmill/db_pwd" = { };
  vaultix.templates."windmill.env" = {
    content = ''
      POSTGRES_USER=postgres
      POSTGRES_DB=windmill
      POSTGRES_PASSWORD=${config.vaultix.placeholder."windmill/db_pwd"}
      DATABASE_URL=postgres://postgres:${
        config.vaultix.placeholder."windmill/db_pwd"
      }@windmill-postgres:5432/windmill?sslmode=disable
    '';
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.oci-containers.backend = "podman";

  systemd.tmpfiles.rules = [
    "d /var/lib/windmill 0755 root root - -"
    "d /var/lib/windmill/postgres 0700 999 999 - -"
    "d /var/lib/windmill/logs 0777 root root - -"
    "d /var/lib/windmill/cache 0777 root root - -"
    "d /var/lib/windmill/lsp-cache 0777 root root - -"
  ];

  virtualisation.oci-containers.containers = {
    # ── 1. Database ──
    windmill-postgres = {
      image = postgresImage;
      extraOptions = [
        "--network=windmill"
        "--shm-size=1g"
      ];
      environmentFiles = [ envFile ];
      volumes = [
        "/var/lib/windmill/postgres:/var/lib/postgresql"
      ];
    };

    # ── 2. Web UI & API Server ──
    windmill-server = {
      image = wmImage;
      ports = [ "127.0.0.1:${toString serverPort}:8000" ];
      extraOptions = [
        "--network=windmill"
        "--add-host=${config.infra.services.hostnames.auth}:host-gateway"
      ];
      dependsOn = [ "windmill-postgres" ];
      environmentFiles = [ envFile ];
      environment = {
        MODE = "server";
        BASE_URL = "https://${config.infra.services.hostnames.windmill}";
        RUST_LOG = "info";
      };
      volumes = [
        "/var/lib/windmill/logs:/tmp/windmill/logs"
      ];
    };

    # ── 3. Primary Worker (Sandboxed & General Execution) ──
    windmill-worker = {
      image = wmImage;
      extraOptions = [
        "--network=windmill"
        "--privileged" # Required for nsjail PID namespace isolation
        "--memory=4g"
      ];
      dependsOn = [ "windmill-postgres" ];
      environmentFiles = [ envFile ];
      environment = {
        MODE = "worker";
        WORKER_GROUP = "default";
        NUM_WORKERS = "3";
        FAVOR_UNSHARE_PID = "true";
        BASE_URL = "https://${config.infra.services.hostnames.windmill}";
        RUST_LOG = "info";
      };
      volumes = [
        "/var/lib/windmill/cache:/tmp/windmill/cache"
        "/var/lib/windmill/logs:/tmp/windmill/logs"
      ];
    };

    # ── 4. Native Worker (Fast In-Process Execution & Flow Dispatch) ──
    windmill-worker-native = {
      image = wmImage;
      extraOptions = [
        "--network=windmill"
        "--memory=2g"
      ];
      dependsOn = [ "windmill-postgres" ];
      environmentFiles = [ envFile ];
      environment = {
        MODE = "worker";
        WORKER_GROUP = "native";
        NATIVE_MODE = "true";
        SLEEP_QUEUE = "200";
        BASE_URL = "https://${config.infra.services.hostnames.windmill}";
        RUST_LOG = "info";
      };
      volumes = [
        "/var/lib/windmill/logs:/tmp/windmill/logs"
      ];
    };

    # ── 5. Extra Services (LSP Code Intelligence & Debugger Gateway) ──
    windmill-extra = {
      image = extraImage;
      ports = [ "127.0.0.1:${toString extraPort}:3000" ];
      extraOptions = [
        "--network=windmill"
      ];
      dependsOn = [ "windmill-server" ];
      environment = {
        ENABLE_LSP = "true";
        ENABLE_MULTIPLAYER = "false";
        ENABLE_DEBUGGER = "true";
        DEBUGGER_PORT = "3003";
        REQUIRE_SIGNED_DEBUG_REQUESTS = "true";
        WINDMILL_BASE_URL = "http://windmill-server:8000";
      };
      volumes = [
        "/var/lib/windmill/lsp-cache:/pyls/.cache"
      ];
    };
  };

  # Podman network, ZFS permission fixup, and symmetrical container dependencies
  systemd.services = {
    create-windmill-network = {
      description = "Create Podman network for Windmill";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.podman}/bin/podman network exists windmill || ${pkgs.podman}/bin/podman network create windmill
      '';
    };

    # Fix permissions on ZFS mount roots so non-root container users can write
    windmill-dataset-perms = {
      description = "Set permissions for Windmill ZFS mounts";
      after = [
        "var-lib-windmill-postgres.mount"
        "var-lib-windmill-logs.mount"
        "var-lib-windmill-cache.mount"
        "var-lib-windmill-lsp-cache.mount"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/chmod 0777 /var/lib/windmill/logs /var/lib/windmill/cache /var/lib/windmill/lsp-cache";
      };
    };
  }
  // (lib.genAttrs allWindmillContainers (_: {
    after = [
      "create-windmill-network.service"
      "windmill-dataset-perms.service"
    ];
    requires = [
      "create-windmill-network.service"
      "windmill-dataset-perms.service"
    ];
    unitConfig.RequiresMountsFor = [
      "/var/lib/windmill/postgres"
      "/var/lib/windmill/logs"
      "/var/lib/windmill/cache"
      "/var/lib/windmill/lsp-cache"
    ];
    serviceConfig.RestartSec = lib.mkDefault "5s";
  }));
}
