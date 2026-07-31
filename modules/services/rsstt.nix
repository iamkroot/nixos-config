{
  config,
  ...
}:
{
  vaultix.secrets."rsstt/telegram_token" = { };
  vaultix.secrets."rsstt/telegram_manager" = { };
  vaultix.templates."rsstt.env" = {
    content = ''
      TOKEN=${config.vaultix.placeholder."rsstt/telegram_token"}
      MANAGER=${config.vaultix.placeholder."rsstt/telegram_manager"}
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers."rsstt" = {
      image = "docker.io/rongronggg9/rss-to-telegram:dev";
      autoStart = true;

      volumes = [
        "/var/lib/rsstt/config:/app/config:z"
      ];

      environment = {
        MULTIUSER = "0";
        MULTIPROCESSING = "1";
      };

      environmentFiles = [
        config.vaultix.templates."rsstt.env".path
      ];

      extraOptions = [
        "--no-healthcheck"
      ];
    };
  };

  systemd.services."${config.virtualisation.oci-containers.backend}-rsstt".serviceConfig = {
    StateDirectory = "rsstt/config";
  };
}
