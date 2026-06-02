{
  config,
  pii,
  lib,
  pkgs,
  myUtils,
  ...
}:
{
  imports = [
    (myUtils.mkCaddyModule "aria2" { authelia = false; })
    (myUtils.mkCaddyModule "ariang" {
      authelia = true;
      extraHostConfig.extraConfig = lib.mkForce ''
        root * ${pkgs.ariang}/share/ariang
        file_server
      '';
    })
  ];

  systemd.tmpfiles.rules = [
    "f /var/lib/aria2/aria2.session 0644 aria2 aria2 - -"
  ];

  services.aria2 = {
    enable = true;
    openPorts = true;
    rpcSecretFile = config.vaultix.secrets."aria2-secret".path;
    settings = {
      enable-rpc = true;
      # Allow connections from local network, direct external access will still be blocked by router
      rpc-listen-all = true;
      rpc-listen-port = config.infra.services.ports.aria2;
      max-connection-per-server = 4;
      split = 4;
      dir = "/media/Downloads";
      continue = true;
      file-allocation = "falloc";
      input = "/var/lib/aria2/aria2.session";
      save-session = "/var/lib/aria2/aria2.session";
      save-session-interval = 60;
      # Helps with some race during boot where ipv4 fails to bind cuz ip address isn't available yet
      disable-ipv6 = true;
    };
  };

  vaultix.secrets."aria2-secret" = {
    file = pii.aria2Secret;
    owner = "aria2";
  };
  users.users.aria2.extraGroups = [ "media" ];

  systemd.services.aria2 = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.UMask = lib.mkForce "0002";
  };

  environment.systemPackages = [ pkgs.ariang ];
}
