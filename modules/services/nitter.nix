{
  config,
  pkgs,
  pii,
  myUtils,
  ...
}:
let
  v = config.infra.versions.shitter;
  port = config.infra.services.ports.nitter;
  domain = config.infra.services.hostnames.nitter;
  vpnProxyPort = config.infra.services.ports.vpn-proxy;
  vpnProxyHost = pii.hosts.homelab1.tailscaleIp;
in
{
  imports = [
    (myUtils.mkCaddyModule "nitter" {
      authelia = false;
    })
  ];

  vaultix.secrets."nitter/hmac_key" = { };

  vaultix.templates."nitter.conf" = {
    mode = "0644";
    content = ''
      [Server]
      hostname = "${domain}"
      title = "Nitter"
      address = "0.0.0.0"
      port = 8080
      https = true
      httpMaxConnections = 100
      staticDir = "./public"

      [Cache]
      listMinutes = 240
      rssMinutes = 10
      redisHost = "nitter-redis"
      redisPort = 6379
      redisPassword = ""
      redisConnections = 20
      redisMaxConnections = 30

      [Config]
      hmacKey = "${config.vaultix.placeholder."nitter/hmac_key"}"
      base64Media = false
      enableRSS = true
      enableRSSUserTweets = true
      enableRSSUserReplies = true
      enableRSSUserMedia = true
      enableRSSUserArticles = true
      enableRSSSearch = true
      enableRSSList = true
      enableDebug = false
      proxy = "http://${vpnProxyHost}:${toString vpnProxyPort}"
      proxyAuth = ""
      apiProxy = ""
      disableTid = false
      maxConcurrentReqs = 2
      maxRetries = 1
      retryDelayMs = 150

      [Preferences]
      theme = "Nitter"
      replaceTwitter = "${domain}"
      proxyVideos = false
      disableVideoPreload = true
      hlsPlayback = true
      infiniteScroll = true
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/nitter 0755 root root -"
    "d /var/lib/nitter/redis 0755 root root -"
    "f /var/lib/nitter/sessions.jsonl 0644 root root -"
  ];

  systemd.services.create-nitter-network = {
    description = "Create Podman network for Nitter";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists nitter || ${pkgs.podman}/bin/podman network create nitter
    '';
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      nitter-redis = {
        image = myUtils.mkImage v.valkey;
        extraOptions = [ "--network=nitter" ];
        volumes = [
          "/var/lib/nitter/redis:/data"
        ];
      };

      nitter = {
        image = myUtils.mkImage v.app;
        ports = [ "127.0.0.1:${toString port}:8080" ];
        extraOptions = [ "--network=nitter" ];
        dependsOn = [ "nitter-redis" ];
        volumes = [
          "${config.vaultix.templates."nitter.conf".path}:/src/nitter.conf:ro"
          "/var/lib/nitter/sessions.jsonl:/src/sessions.jsonl:ro"
        ];
      };
    };
  };

  systemd.services."${config.virtualisation.oci-containers.backend}-nitter-redis" = {
    after = [
      "network.target"
      "var-lib-nitter.mount"
      "create-nitter-network.service"
    ];
    requires = [
      "var-lib-nitter.mount"
      "create-nitter-network.service"
    ];
    preStart = ''
      mkdir -p /var/lib/nitter/redis
      chmod 0755 /var/lib/nitter /var/lib/nitter/redis
    '';
  };

  systemd.services."${config.virtualisation.oci-containers.backend}-nitter" = {
    after = [
      "network.target"
      "var-lib-nitter.mount"
      "vaultix-activate.service"
      "create-nitter-network.service"
      "sing-box.service"
    ];
    wants = [
      "vaultix-activate.service"
      "sing-box.service"
    ];
    requires = [
      "var-lib-nitter.mount"
      "create-nitter-network.service"
    ];
    preStart = ''
      mkdir -p /var/lib/nitter
      # Ensure sessions.jsonl exists with read permissions (0644) for container user
      if [ ! -f /var/lib/nitter/sessions.jsonl ]; then
        touch /var/lib/nitter/sessions.jsonl
        chmod 0644 /var/lib/nitter/sessions.jsonl
      fi
    '';
  };
}
