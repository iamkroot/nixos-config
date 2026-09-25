{
  config,
  pkgs,
  pii,
  myUtils,
  lib,
  inputs,
  ...
}:
let
  chatlumeConfig = pii.chatlume.config;

  exportsDir = pii.chatlume.exportsDir;
  configDir = pkgs.writeTextDir "config.json" (builtins.toJSON chatlumeConfig);
in
{
  imports = [
    (myUtils.mkCaddyModule "chatlume" {
      authelia = true;
      extraHostConfig = {
        extraConfig = ''
          # Dynamic config.json generated from pii
          handle /config.json {
            header Content-Type application/json
            header Cache-Control "no-cache"
            root * ${configDir}
            file_server
          }

          # Lazy-loaded WhatsApp chat export directory
          ${lib.optionalString (exportsDir != null) ''
            handle_path /exports* {
              root * ${exportsDir}
              file_server
            }
          ''}

          # ChatLume static web application
          handle {
            root * ${inputs.chatlume}
            file_server
          }
        '';
      };
    })
  ];

  myAuthelia.accessRules = [
    {
      domain = [ config.infra.services.hostnames.chatlume ];
      policy = "one_factor";
      subject = [
        "group:chatlume_users"
      ];
    }
  ];

  users.users.caddy.extraGroups = [ "media" ];

  systemd.tmpfiles.rules = lib.optional (exportsDir != null) "d ${exportsDir} 0775 dufs media - -";
}
