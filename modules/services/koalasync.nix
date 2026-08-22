{
  config,
  lib,
  myUtils,
  pii,
  ...
}:
let
  port = config.infra.services.ports.koalasync;
  # FIXME: Need better util for "optional" secrets like these
  hasSalt = pii.secrets ? koalasync-salt && builtins.pathExists pii.secrets.koalasync-salt;
  hasMetricsToken =
    pii.secrets ? koalasync-metrics-token && builtins.pathExists pii.secrets.koalasync-metrics-token;
in
{
  imports = [
    (myUtils.mkCaddyModule "koalasync" { authelia = false; })
  ];

  vaultix.secrets =
    (lib.optionalAttrs hasSalt {
      koalasync_salt = {
        file = pii.secrets.koalasync-salt;
      };
    })
    // (lib.optionalAttrs hasMetricsToken {
      koalasync_metrics_token = {
        file = pii.secrets.koalasync-metrics-token;
      };
    });

  vaultix.templates = lib.optionalAttrs (hasSalt || hasMetricsToken) {
    "koalasync.env" = {
      content = ''
        ${lib.optionalString hasSalt "SERVER_SALT=${config.vaultix.placeholder.koalasync_salt}"}
        ${lib.optionalString hasMetricsToken "ADMIN_METRICS_TOKEN=${config.vaultix.placeholder.koalasync_metrics_token}"}
      '';
    };
  };

  virtualisation.oci-containers.containers."koalasync" = {
    image = "ghcr.io/shik3i/koalasync:latest";
    ports = [ "127.0.0.1:${toString port}:3000" ];
    environment = {
      PORT = "3000";
      MAX_ROOMS = "1000";
      MAX_PEERS_PER_ROOM = "25";
      MIN_VERSION = "1.0.0";
      DEBUG_LOGGING = "0";
    };
    environmentFiles = lib.optionals (hasSalt || hasMetricsToken) [
      config.vaultix.templates."koalasync.env".path
    ];
  };
}
