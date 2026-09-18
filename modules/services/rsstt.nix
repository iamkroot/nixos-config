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
      image = "docker.io/rongronggg9/rss-to-telegram:dev@sha256:75d000bdadf8f9934a4467e2e9a03f0d5671fa6d2e7f8299064ae82ecf64f90f";
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
