{
  config,
  pii,
  lib,
  ...
}:
{
  services.aria2 = {
    enable = true;
    openPorts = true;
    rpcSecretFile = config.vaultix.secrets."aria2-secret".path;
    settings = {
      enable-rpc = true;
      rpc-listen-all = true;
      max-connection-per-server = 8;
    };
  };
  services.caddy.virtualHosts."${config.infra.services.hostnames.aria2}" = {
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString config.infra.services.ports.aria2}
    '';
    logFormat = ''
      output file /var/log/caddy/access-${config.infra.services.hostnames.aria2}.log {
        roll_size 50mb
        roll_keep 5
      }
    '';
  };
  vaultix.secrets."aria2-secret" = {
    file = pii.aria2Secret;
    owner = "aria2";
  };
  users.users.aria2.extraGroups = [ "media" ];
  systemd.services.aria2.serviceConfig.UMask = lib.mkForce "0002";
}
