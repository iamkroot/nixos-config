{
  config,
  pkgs,
  pii,
  myUtils,
  hostKey,
  lib,
  ...
}:
let
  cfg = config.infra.dns.adguard;
  isLocal = cfg.location == "local" || cfg.location == "homelab1" || cfg.location == hostKey;
  targetHost = pii.${cfg.location}.localIp;

  caddyConfig =
    (myUtils.mkCaddyModule "adguard" {
      authelia = true;
      inherit targetHost;
      bypassAuthPaths = [ "/dns-query*" ];
    })
      { inherit config pii; };
in
{
  config = lib.mkIf (cfg.enable && !isLocal) (
    lib.mkMerge [
      caddyConfig
      {
        vaultix.secrets.acme-ssh-key = lib.mkIf cfg.syncCerts {
          file = pii.secrets.acme-ssh-key;
          owner = "acme";
          group = "acme";
          mode = "0400";
        };

        security.acme.certs."${config.infra.domain}".postRun = lib.mkIf cfg.syncCerts ''
          SSH="${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new -i ${config.vaultix.secrets.acme-ssh-key.path}"
          SCP="${pkgs.openssh}/bin/scp -O -o StrictHostKeyChecking=accept-new -i ${config.vaultix.secrets.acme-ssh-key.path}"

          $SSH root@${targetHost} 'mkdir -p /etc/adguardhome/ssl'
          $SCP fullchain.pem root@${targetHost}:/etc/adguardhome/ssl/fullchain.pem
          $SCP key.pem root@${targetHost}:/etc/adguardhome/ssl/key.pem
          $SSH root@${targetHost} 'chown -R adguardhome:adguardhome /etc/adguardhome/ssl && chmod 700 /etc/adguardhome/ssl && chmod 600 /etc/adguardhome/ssl/* && /etc/init.d/adguardhome restart'
        '';
      }
    ]
  );
}
