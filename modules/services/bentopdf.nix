{
  config,
  pkgs,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "bentopdf" {
      authelia = true;
      extraHostConfig.extraConfig = ''
        root * ${pkgs.bentopdf}
        try_files {path} /index.html
        file_server

        @static {
          path_regexp static \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$
        }
        handle @static {
          header {
            Cache-Control "public, immutable"
          }
          header Cache-Control max-age=31536000
        }
      '';
    })
  ];

  myAuthelia.accessRules = [
    {
      domain = [ config.infra.services.hostnames.bentopdf ];
      policy = "one_factor";
    }
  ];

  environment.systemPackages = [ pkgs.bentopdf ];
}
