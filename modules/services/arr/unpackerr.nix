{
  config,
  pii,
  ...
}:
let
  downloadsDir = "${pii.storage.media_main.mountpoint}/Downloads";
in
{
  services.unpackerr = {
    enable = true;
    user = "unpackerr";
    group = "media";
    settings = {
      file_mode = "0664";
      dir_mode = "0775";
      sonarr = [
        {
          url = "http://127.0.0.1:${toString config.infra.services.ports.sonarr}";
          paths = [
            "${downloadsDir}/sonarr"
            downloadsDir
          ];
          protocols = "torrent,TorrentDownloadProtocol";
        }
      ];
      radarr = [
        {
          url = "http://127.0.0.1:${toString config.infra.services.ports.radarr}";
          paths = [
            "${downloadsDir}/radarr"
            downloadsDir
          ];
          protocols = "torrent,TorrentDownloadProtocol";
        }
      ];
    };
  };

  systemd.services.unpackerr.serviceConfig.EnvironmentFile = [
    config.vaultix.templates."unpackerr.env".path
  ];

  vaultix.secrets."sonarr-key" = {
    file = pii.secrets.sonarr-key;
  };
  vaultix.secrets."radarr-key" = {
    file = pii.secrets.radarr-key;
  };

  vaultix.templates."unpackerr.env" = {
    content = ''
      UN_SONARR_0_API_KEY=${config.vaultix.placeholder.sonarr-key}
      UN_RADARR_0_API_KEY=${config.vaultix.placeholder.radarr-key}
    '';
    group = "media";
    mode = "640";
  };
}
