{
  config,
  lib,
  myUtils,
  pii,
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

  yamlFormat = pkgs.formats.yaml { };
  windmillConfigFile = yamlFormat.generate "windmill-config.yaml" config.myWindmill.settings;

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
    ({ lib, ... }: {
      options.myWindmill = {
        enableConfigSync = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to declaratively sync instance configuration (windmill-config.yaml) to the database.";
        };

        settings = lib.mkOption {
          type = lib.types.submodule {
            freeformType = yamlFormat.type;
          };
          default = { };
          description = ''
            Declarative instance-level configuration for Windmill (global_settings, worker_configs).
            Synced to the database via `windmill sync-config` on deployment.
          '';
        };
      };
    })
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

  myAuthelia.accessRules = [
    {
      domain = config.infra.services.hostnames.windmill;
      policy = "one_factor";
      subject = [
        "group:windmill_users"
      ];
    }
  ];

  myAuthelia.oidcClients = [
    (myUtils.mkAutheliaOIDC pii "windmill" {
      scopes = [
        "openid"
        "profile"
        "email"
        "groups"
      ];
      redirect_uris = [
        "https://${config.infra.services.hostnames.windmill}/user/login_callback/authelia"
      ];
      token_endpoint_auth_method = "client_secret_basic";
    })
  ];

  myWindmill.settings = {
    global_settings = {
      base_url = lib.mkDefault "https://${config.infra.services.hostnames.windmill}";
      smtp_settings = {
        smtp_host = lib.mkDefault pii.smtpHost;
        smtp_port = lib.mkDefault 587;
        smtp_username = lib.mkDefault pii.smtpEmail;
        smtp_password = {
          envRef = "SMTP_PASSWORD";
        };
        smtp_from = lib.mkDefault pii.smtpEmail;
        smtp_tls_implicit = lib.mkDefault false;
        smtp_disable_tls = lib.mkDefault false;
        smtp_clicktracking_off = lib.mkDefault true;
      };
      oauths = {
        authelia = {
          id = pii.authelia.windmill.client-id;
          secret = {
            envRef = "AUTHELIA_CLIENT_SECRET";
          };
          display_name = "Authelia";
          connect_config = {
            auth_url = "https://${config.infra.services.hostnames.auth}/api/oidc/authorization";
            token_url = "https://${config.infra.services.hostnames.auth}/api/oidc/token";
            scopes = [
              "openid"
              "profile"
              "email"
              "groups"
            ];
          };
          login_config = {
            auth_url = "https://${config.infra.services.hostnames.auth}/api/oidc/authorization";
            token_url = "https://${config.infra.services.hostnames.auth}/api/oidc/token";
            userinfo_url = "https://${config.infra.services.hostnames.auth}/api/oidc/userinfo";
            scopes = [
              "openid"
              "profile"
              "email"
              "groups"
            ];
          };
        };
      };
    };
    worker_configs = {
      default = {
        worker_tags = lib.mkDefault [
          "python3"
          "bun"
          "go"
          "bash"
        ];
      };
      native = {
        worker_tags = lib.mkDefault [ "nativets" ];
      };
    };
  };

  vaultix.secrets."windmill/db_pwd" = { };
  vaultix.secrets."windmill/smtp_app_pwd" = { };
  vaultix.secrets."windmill/sso_secret" = { };
  vaultix.templates."windmill.env" = {
    content = ''
      POSTGRES_USER=postgres
      POSTGRES_DB=windmill
      POSTGRES_PASSWORD=${config.vaultix.placeholder."windmill/db_pwd"}
      DATABASE_URL=postgres://postgres:${
        config.vaultix.placeholder."windmill/db_pwd"
      }@windmill-postgres:5432/windmill?sslmode=disable
      SMTP_PASSWORD=${config.vaultix.placeholder."windmill/smtp_app_pwd"}
      AUTHELIA_CLIENT_SECRET=${config.vaultix.placeholder."windmill/sso_secret"}
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
  systemd.services = lib.mkMerge [
    {
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

      podman-windmill-server = {
        after = [
          "authelia-main.service"
          "caddy.service"
        ];
        wants = [
          "authelia-main.service"
          "caddy.service"
        ];
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

      windmill-config-sync = lib.mkIf config.myWindmill.enableConfigSync {
        description = "Sync Windmill Instance Configuration to DB";
        after = [
          "create-windmill-network.service"
          "windmill-dataset-perms.service"
          "podman-windmill-postgres.service"
          "podman-windmill-server.service"
        ];
        wants = [ "podman-windmill-server.service" ];
        requires = [
          "create-windmill-network.service"
          "windmill-dataset-perms.service"
          "podman-windmill-postgres.service"
        ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ windmillConfigFile ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "5s";
        };
        script = ''
          # 1. Wait for Windmill Postgres container to become ready (max 30s)
          for i in $(${pkgs.coreutils}/bin/seq 1 30); do
            if ${pkgs.podman}/bin/podman exec windmill-postgres pg_isready -U postgres -d windmill >/dev/null 2>&1; then
              break
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done

          # 2. Wait for server to run migrations so global_settings table exists (max 60s)
          for i in $(${pkgs.coreutils}/bin/seq 1 60); do
            if ${pkgs.podman}/bin/podman exec windmill-postgres psql -U postgres -d windmill -c "SELECT 1 FROM global_settings LIMIT 1;" >/dev/null 2>&1; then
              break
            fi
            ${pkgs.coreutils}/bin/sleep 2
          done

          # 3. Apply declarative instance configuration
          ${pkgs.podman}/bin/podman run --rm \
            --network=windmill \
            --env-file=${envFile} \
            -v ${windmillConfigFile}:/config/windmill-config.yaml:ro \
            ${wmImage} windmill sync-config /config/windmill-config.yaml
        '';
      };
    }
    (lib.genAttrs allWindmillContainers (_: {
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
      serviceConfig.Restart = lib.mkForce "always"; # windmill likes to self-restart on certain config changes
      serviceConfig.RestartSec = lib.mkDefault "5s";
    }))
  ];
}
