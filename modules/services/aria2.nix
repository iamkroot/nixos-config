{
  config,
  pii,
  lib,
  pkgs,
  myUtils,
  ...
}:
{
  # FIXME: Needed to work around https://github.com/NixOS/nixpkgs/issues/523144
  nixpkgs.overlays = [
    (final: prev: {
      ariang = prev.ariang.override {
        buildNpmPackage =
          args:
          prev.buildNpmPackage (
            args
            // {
              version = "1.3.14";
              src = final.fetchFromGitHub {
                owner = "timhae";
                repo = "AriaNg";
                rev = "7d0538b";
                hash = "sha256-iUgUT1Vq0KExDT+xSrbvZDDs48GOk+gE6wPAKooFhuU=";
              };
              npmDepsHash = "sha256-XHoPPrebNgGZnVQmA0d5OeR+ZWJQEdZU4Ibcbd80/oM=";
            }
          );
      };
    })
  ];
  imports = [
    (myUtils.mkCaddyModule "aria2" {
      # authelia = false; doesn't work due to mkForce below
      extraHostConfig.extraConfig = ''
        @denied not remote_ip private_ranges
        abort @denied
        reverse_proxy 127.0.0.1:${toString config.infra.services.ports.aria2}
      '';
    })
    (myUtils.mkCaddyModule "ariang" {
      # authelia = true; doesn't work due to mkForce below
      extraHostConfig.extraConfig = ''
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
      rpc-allow-origin-all = true;
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
